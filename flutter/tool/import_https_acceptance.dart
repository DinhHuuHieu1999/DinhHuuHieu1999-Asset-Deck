import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../lib/api/asset.dart';
import '../lib/api/asset_api.dart';
import '../lib/api/asset_import.dart';
import '../lib/api/asset_store.dart';
import 'client_https_acceptance.dart' show check, validateDriverArgs;
import 'export_https_acceptance.dart' show pythonDigest, validatePython;
import 'native_https_seed.dart' show verifyNativeMarker;

/// Actual client against a marker-owned synthetic HTTPS target; never retries.
Future<void> main(List<String> args) async {
  final clients = <AssetApi>[];
  final probe = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    check(args.length == 4);
    final endpoint = validateDriverArgs(args.sublist(0, 3));
    validatePython(args[3]);
    await verifyNativeMarker(probe, endpoint, args[2]);
    final suffix = List.generate(
      12,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final a = AssetApi(endpoint), b = AssetApi(endpoint);
    clients.addAll([a, b]);
    for (final entry in [('a', a), ('b', b)]) {
      await entry.$2.register(
        email: '${entry.$1}$suffix@example.invalid',
        username: '${entry.$1}$suffix',
        name: 'Synthetic import client',
        password: 'Synthetic-$suffix-42!',
      );
    }
    await a.create(
      const AssetInput(
        name: 'Synthetic HTTPS import',
        category: 'fixture',
        serial: '%_1',
        status: 'stored',
        notes: 'Synthetic only',
      ),
    );
    final snapshot = await a.exportInventory(
      digest: (bytes) => pythonDigest(args[3], bytes),
    );
    check(snapshot.count == 1);
    final draft = AssetImportDraft.prepare(
      snapshot: snapshot,
      accountId: b.account!.id,
      requestId: createAssetImportRequestId(),
    );
    check((await b.list(query: '', status: '', offset: 0)).items.isEmpty);
    final revision = b.sessionRevision;
    final first = await b.importInventory(draft, sessionRevision: revision);
    final replay = await b.importInventory(draft, sessionRevision: revision);
    check(
      first.recordIds.length == 1 &&
          jsonEncode(first.recordIds) == jsonEncode(replay.recordIds),
    );
    final imported = (await b.list(query: '', status: '', offset: 0)).items;
    check(
      imported.length == 1 &&
          imported.single.id == first.recordIds.single &&
          imported.single.input.name == snapshot.records.single.input.name,
    );
    check((await a.list(query: '', status: '', offset: 0)).items.length == 1);
    await a.update(
      snapshot.records.single,
      const AssetInput(
        name: 'Synthetic changed content',
        category: 'fixture',
        serial: '%_1',
        status: 'stored',
        notes: 'Changed only in synthetic fixture',
      ),
    );
    final changed = await a.exportInventory(
      digest: (bytes) => pythonDigest(args[3], bytes),
    );
    final conflict = AssetImportDraft.prepare(
      snapshot: changed,
      accountId: b.account!.id,
      requestId: draft.requestId,
    );
    var conflicted = false;
    try {
      await b.importInventory(conflict, sessionRevision: revision);
    } on AssetFailure catch (error) {
      conflicted = error.statusCode == 409;
    }
    check(conflicted);
    check(
      (await b.list(query: '', status: '', offset: 0)).items.single.id ==
          first.recordIds.single,
    );
    // A cross-account operation must be refused locally, not silently retargeted.
    var refused = false;
    try {
      await a.importInventory(draft, sessionRevision: a.sessionRevision);
    } on AssetFailure catch (error) {
      refused = error.definitelyNotSent;
    }
    check(refused);
    final independent = AssetImportDraft.prepare(
      snapshot: snapshot,
      accountId: a.account!.id,
      requestId: draft.requestId,
    );
    final own = await a.importInventory(
      independent,
      sessionRevision: a.sessionRevision,
    );
    check(own.recordIds.single != first.recordIds.single);
    check((await a.list(query: '', status: '', offset: 0)).items.length == 2);
    b.signOut();
    refused = false;
    try {
      await b.importInventory(draft, sessionRevision: revision);
    } on AssetFailure {
      refused = true;
    }
    check(refused);
    stdout.writeln(
      jsonEncode({
        'status': 'completed',
        'syntheticOnly': true,
        'owners': 2,
        'imported': 2,
        'exactReplay': true,
        'conflict': true,
        'accountBound': true,
        'sessionInvalidation': true,
      }),
    );
  } catch (_) {
    stderr.writeln('Synthetic import client failed; no automatic retry.');
    exitCode = 1;
  } finally {
    probe.close(force: true);
    for (final client in clients) {
      client.close();
    }
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../lib/api/asset.dart';
import '../lib/api/asset_api.dart';
import '../lib/api/asset_import.dart' show createAssetImportRequestId;
import '../lib/api/asset_import_v3.dart';
import '../lib/api/asset_export_v3.dart';
import '../lib/api/asset_dates.dart';
import '../lib/api/asset_store.dart';
import 'client_https_acceptance.dart' show check, validateDriverArgs;
import 'export_https_acceptance.dart' show pythonDigest, validatePython;
import 'native_https_seed.dart' show verifyNativeMarker;

/// Compare all editable fields, dates and fresh identities after verified export.
void verifyReexport(
  AssetExportV3 source,
  AssetExportV3 target,
  List<String> ids,
) {
  check(source.count == target.count && target.count == ids.length);
  for (var i = 0; i < source.count; i++) {
    final original = source.records[i];
    final imported = target.records.singleWhere(
      (row) => row.asset.id == ids[i],
    );
    check(imported.asset.id != original.asset.id);
    check(imported.asset.version == 1);
    check(
      jsonEncode(imported.asset.input.toJson()) ==
          jsonEncode(original.asset.input.toJson()),
    );
    check(imported.dates.purchasedOn == original.dates.purchasedOn);
    check(imported.dates.warrantyExpiresOn == original.dates.warrantyExpiresOn);
    check(imported.location == original.location);
  }
}

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
    final created = await a.create(
      const AssetInput(
        name: 'Synthetic HTTPS import',
        category: 'fixture',
        serial: '%_1',
        status: 'stored',
        notes: 'Synthetic only',
      ),
    );
    await a.updateDates(
      await a.readDates(created.id),
      const AssetDatesInput(
        purchasedOn: '2024-02-29',
        warrantyExpiresOn: '2028-01-01',
      ),
    );
    await a.updateLocation(
      await a.readLocation(created.id),
      'Synthetic room %_1',
    );
    final snapshot = await a.exportInventoryV3(
      digest: (bytes) => pythonDigest(args[3], bytes),
    );
    check(snapshot.count == 1);
    final draft = AssetImportV3Draft.prepare(
      snapshot: snapshot,
      accountId: b.account!.id,
      requestId: createAssetImportRequestId(),
    );
    check((await b.list(query: '', status: '', offset: 0)).items.isEmpty);
    final revision = b.sessionRevision;
    final first = await b.importInventoryV3(draft, sessionRevision: revision);
    final replay = await b.importInventoryV3(draft, sessionRevision: revision);
    check(
      first.recordIds.length == 1 &&
          jsonEncode(first.recordIds) == jsonEncode(replay.recordIds),
    );
    final imported = (await b.list(query: '', status: '', offset: 0)).items;
    check(
      imported.length == 1 &&
          imported.single.id == first.recordIds.single &&
          imported.single.input.name ==
              snapshot.records.single.asset.input.name,
    );
    check((await a.list(query: '', status: '', offset: 0)).items.length == 1);
    final importedDates = await b.readDates(first.recordIds.single);
    check(
      importedDates.version == 1 &&
          importedDates.input.purchasedOn == '2024-02-29' &&
          importedDates.input.warrantyExpiresOn == '2028-01-01',
    );
    final reexport = await b.exportInventoryV3(
      digest: (bytes) => pythonDigest(args[3], bytes),
    );
    verifyReexport(snapshot, reexport, first.recordIds);
    await a.updateDates(
      await a.readDates(created.id),
      const AssetDatesInput(
        purchasedOn: '2024-02-29',
        warrantyExpiresOn: '2028-01-02',
      ),
    );
    final changed = await a.exportInventoryV3(
      digest: (bytes) => pythonDigest(args[3], bytes),
    );
    final conflict = AssetImportV3Draft.prepare(
      snapshot: changed,
      accountId: b.account!.id,
      requestId: draft.requestId,
    );
    var conflicted = false;
    try {
      await b.importInventoryV3(conflict, sessionRevision: revision);
    } on AssetFailure catch (error) {
      conflicted = error.statusCode == 409;
    }
    check(conflicted);
    check(
      (await b.list(query: '', status: '', offset: 0)).items.single.id ==
          first.recordIds.single,
    );
    await a.updateDates(
      await a.readDates(created.id),
      const AssetDatesInput(
        purchasedOn: '2024-02-29',
        warrantyExpiresOn: '2028-01-01',
      ),
    );
    await a.updateLocation(await a.readLocation(created.id), 'Changed room');
    final moved = await a.exportInventoryV3(
      digest: (bytes) => pythonDigest(args[3], bytes),
    );
    final movedDraft = AssetImportV3Draft.prepare(
      snapshot: moved,
      accountId: b.account!.id,
      requestId: draft.requestId,
    );
    conflicted = false;
    try {
      await b.importInventoryV3(movedDraft, sessionRevision: revision);
    } on AssetFailure catch (error) {
      conflicted = error.statusCode == 409;
    }
    check(conflicted);
    final retained = await b.exportInventoryV3(
      digest: (bytes) => pythonDigest(args[3], bytes),
    );
    verifyReexport(snapshot, retained, first.recordIds);
    // A cross-account operation must be refused locally, not silently retargeted.
    var refused = false;
    try {
      await a.importInventoryV3(draft, sessionRevision: a.sessionRevision);
    } on AssetFailure catch (error) {
      refused = error.definitelyNotSent;
    }
    check(refused);
    final independent = AssetImportV3Draft.prepare(
      snapshot: snapshot,
      accountId: a.account!.id,
      requestId: draft.requestId,
    );
    final own = await a.importInventoryV3(
      independent,
      sessionRevision: a.sessionRevision,
    );
    check(own.recordIds.single != first.recordIds.single);
    check((await a.list(query: '', status: '', offset: 0)).items.length == 2);
    b.signOut();
    refused = false;
    try {
      await b.importInventoryV3(draft, sessionRevision: revision);
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
        'datesPreserved': true,
        'completeReexport': true,
        'dateOnlyConflict': true,
        'locationPreserved': true,
        'locationOnlyConflict': true,
        'schemaVersion': 3,
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

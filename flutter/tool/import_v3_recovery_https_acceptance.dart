import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../lib/api/asset.dart';
import '../lib/api/asset_api.dart';
import '../lib/api/asset_import.dart';
import '../lib/api/asset_import_v3_recovery.dart';
import '../lib/api/asset_import_v3.dart';
import '../lib/api/asset_dates.dart';
import '../lib/api/asset_store.dart';
import 'client_https_acceptance.dart' show check, validateDriverArgs;
import 'export_https_acceptance.dart' show pythonDigest, validatePython;
import 'native_https_seed.dart' show verifyNativeMarker;

/// Validate fixed stage/target before network access or file mutation.
Uri validateRecoveryArgs(List<String> args) {
  check(args.length == 6 && ['prepare', 'submit', 'replay'].contains(args[4]));
  final endpoint = validateDriverArgs(args.sublist(0, 3));
  validatePython(args[3]);
  check(
    Directory(args[5]).isAbsolute &&
        FileSystemEntity.typeSync(args[5], followLinks: false) ==
            FileSystemEntityType.directory,
  );
  return endpoint;
}

/// Retain synthetic files exclusively; never overwrite earlier evidence.
Future<void> writeNew(File file, String text) async {
  await file.create(exclusive: true);
  await file.writeAsString(text, encoding: utf8, flush: true);
  check(await file.readAsString(encoding: utf8) == text);
}

/// Bounded local fixture input, with no symbolic link accepted.
Future<String> readBounded(File file, int limit) async {
  check(
    await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.file,
  );
  final bytes = <int>[];
  await for (final chunk in file.openRead()) {
    check(bytes.length + chunk.length <= limit);
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes);
}

/// Invoke stages in distinct processes; no automatic import retry.
Future<void> main(List<String> args) async {
  final clients = <AssetApi>[];
  final probe = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final endpoint = validateRecoveryArgs(args);
    await verifyNativeMarker(probe, endpoint, args[2]);
    final control = File('${args[5]}/recovery-control.json');
    final saved = File('${args[5]}/private-import-recovery.json');
    final stage = args[4];
    if (stage == 'prepare') {
      check(!await control.exists() && !await saved.exists());
      final suffix = List.generate(
        12,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final source = AssetApi(endpoint), target = AssetApi(endpoint);
      clients.addAll([source, target]);
      for (final entry in [('a', source), ('b', target)]) {
        await entry.$2.register(
          email: '${entry.$1}$suffix@example.invalid',
          username: '${entry.$1}$suffix',
          name: 'Synthetic recovery',
          password: 'Synthetic-$suffix-42!',
        );
      }
      final created = await source.create(
        const AssetInput(
          name: 'Synthetic recovery asset',
          category: 'fixture',
          serial: 'synthetic-recovery',
          status: 'stored',
          notes: 'Private fixture only',
        ),
      );
      await source.updateDates(
        await source.readDates(created.id),
        const AssetDatesInput(
          purchasedOn: '2024-02-29',
          warrantyExpiresOn: '2028-01-01',
        ),
      );
      await source.updateLocation(
        await source.readLocation(created.id),
        'Recovery room %_1',
      );
      final snapshot = await source.exportInventoryV3(
        digest: (bytes) => pythonDigest(args[3], bytes),
      );
      final draft = AssetImportV3Draft.prepare(
        snapshot: snapshot,
        accountId: target.account!.id,
        requestId: createAssetImportRequestId(),
      );
      final recovery = await AssetImportV3Recovery.prepare(
        draft: draft,
        apiBase: endpoint.toString(),
        digest: (bytes) => pythonDigest(args[3], bytes),
      );
      await writeNew(saved, recovery.json);
      await writeNew(
        control,
        jsonEncode({
          'fixtureId': args[2],
          'endpoint': endpoint.toString(),
          'sourceIdentifier': 'a$suffix',
          'identifier': 'b$suffix',
          'password': 'Synthetic-$suffix-42!',
          'requestId': draft.requestId,
          'accountId': target.account!.id,
        }),
      );
      stdout.writeln(jsonEncode({'stage': stage, 'saved': true}));
      return;
    }
    final data = jsonDecode(await readBounded(control, 8192));
    check(
      data is Map &&
          data['fixtureId'] == args[2] &&
          data['endpoint'] == endpoint.toString(),
    );
    final api = AssetApi(endpoint);
    clients.add(api);
    await api.login(data['identifier'] as String, data['password'] as String);
    check(api.account!.id == data['accountId']);
    final recovery = await AssetImportV3Recovery.parse(
      await readBounded(saved, AssetImportV3Recovery.maxBytes),
      currentApiBase: endpoint.toString(),
      currentAccountId: api.account!.id,
      digest: (bytes) => pythonDigest(args[3], bytes),
    );
    check(recovery.draft.requestId == data['requestId']);
    if (stage == 'submit') {
      check((await api.list(query: '', status: '', offset: 0)).items.isEmpty);
      var uncertain = false;
      try {
        await api.importInventoryV3(
          recovery.draft,
          sessionRevision: api.sessionRevision,
        );
      } on AssetFailure catch (failure) {
        uncertain = !failure.definitelyNotSent;
      }
      check(uncertain);
      stdout.writeln(jsonEncode({'stage': stage, 'uncertain': true}));
      return;
    }
    final fileJson = await readBounded(saved, AssetImportV3Recovery.maxBytes);
    var endpointRefused = false;
    try {
      await AssetImportV3Recovery.parse(
        fileJson,
        currentApiBase: '${endpoint.toString()}/different',
        currentAccountId: api.account!.id,
        digest: (bytes) => pythonDigest(args[3], bytes),
      );
    } on FormatException {
      endpointRefused = true;
    }
    check(endpointRefused);
    final other = AssetApi(endpoint);
    clients.add(other);
    await other.login(
      data['sourceIdentifier'] as String,
      data['password'] as String,
    );
    final otherBefore = await other.list(query: '', status: '', offset: 0);
    check(otherBefore.items.length == 1);
    var ownerRefused = false;
    try {
      await AssetImportV3Recovery.parse(
        fileJson,
        currentApiBase: endpoint.toString(),
        currentAccountId: other.account!.id,
        digest: (bytes) => pythonDigest(args[3], bytes),
      );
    } on StateError {
      ownerRefused = true;
    }
    check(ownerRefused);
    final before = (await api.list(query: '', status: '', offset: 0)).items;
    check(before.length == 1);
    final beforeLocation = await api.readLocation(before.single.id);
    check(beforeLocation.location == 'Recovery room %_1');
    final beforeDates = await api.readDates(before.single.id);
    check(
      beforeDates.input.purchasedOn == '2024-02-29' &&
          beforeDates.input.warrantyExpiresOn == '2028-01-01',
    );
    final receipt = await api.importInventoryV3(
      recovery.draft,
      sessionRevision: api.sessionRevision,
    );
    final after = (await api.list(query: '', status: '', offset: 0)).items;
    check(
      after.length == 1 &&
          receipt.recordIds.single == before.single.id &&
          after.single.id == before.single.id &&
          jsonEncode(after.single.input.toJson()) ==
              jsonEncode(before.single.input.toJson()),
    );
    final afterDates = await api.readDates(after.single.id);
    check(
      afterDates.version == beforeDates.version &&
          afterDates.input.purchasedOn == beforeDates.input.purchasedOn &&
          afterDates.input.warrantyExpiresOn ==
              beforeDates.input.warrantyExpiresOn,
    );
    final afterLocation = await api.readLocation(after.single.id);
    check(
      afterLocation.location == beforeLocation.location &&
          afterLocation.version == beforeLocation.version,
    );
    final otherAfter = await other.list(query: '', status: '', offset: 0);
    check(
      otherAfter.items.single.id == otherBefore.items.single.id &&
          jsonEncode(otherAfter.items.single.input.toJson()) ==
              jsonEncode(otherBefore.items.single.input.toJson()),
    );
    stdout.writeln(
      jsonEncode({
        'stage': stage,
        'sameIds': true,
        'unchangedFields': true,
        'unchangedDates': true,
        'unchangedLocation': true,
        'count': 1,
      }),
    );
  } catch (_) {
    stderr.writeln('Synthetic recovery stage failed; no automatic retry.');
    exitCode = 1;
  } finally {
    probe.close(force: true);
    for (final client in clients) {
      client.close();
    }
  }
}

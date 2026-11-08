import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../lib/api/asset.dart';
import '../lib/api/asset_api.dart';
import '../lib/api/asset_saved_filter.dart';
import 'client_https_acceptance.dart' show check, validateDriverArgs;
import 'native_https_seed.dart' show verifyNativeMarker;
import 'import_recovery_https_acceptance.dart' show readBounded, writeNew;

/// Reject ordinary targets and unknown stages before network or file access.
Uri validateSavedRestartArgs(List<String> args) {
  check(args.length == 5 && ['prepare', 'verify'].contains(args[3]));
  final endpoint = validateDriverArgs(args.sublist(0, 3));
  check(
    Directory(args[4]).isAbsolute &&
        FileSystemEntity.typeSync(args[4], followLinks: false) ==
            FileSystemEntityType.directory,
  );
  return endpoint;
}

/// Compare every stored public definition field, including fixed date predicates.
Map<String, Object?> savedRestartSnapshot(AssetSavedFilter value) => {
  'id': value.id,
  'name': value.name,
  'version': value.version,
  'schemaVersion': 1,
  'query': {
    for (final key in AssetSavedFilterQuery.fields)
      key: value.query.values[key],
  },
};

Map<String, Object?> _assetSnapshot(AssetRecord value) => {
  'id': value.id,
  ...value.input.toJson(),
  'version': value.version,
  'createdAt': value.createdAt.toIso8601String(),
  'updatedAt': value.updatedAt.toIso8601String(),
};

/// Two separate client processes reauthenticate; credentials remain only in the private fixture.
Future<void> main(List<String> args) async {
  final clients = <AssetApi>[];
  final probe = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final endpoint = validateSavedRestartArgs(args);
    await verifyNativeMarker(probe, endpoint, args[2]);
    final file = File('${args[4]}/private-saved-restart.json');
    final stage = args[3];
    if (stage == 'prepare') {
      check(!await file.exists());
      final suffix = List.generate(
        12,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final owners = <Map<String, Object?>>[];
      for (final label in ['a', 'b']) {
        final api = AssetApi(endpoint);
        clients.add(api);
        final email = '$label$suffix@example.invalid',
            password = 'Synthetic-$suffix-42!';
        await api.register(
          email: email,
          username: '$label$suffix',
          name: 'Synthetic restart owner',
          password: password,
        );
        await api.create(
          AssetInput(
            name: 'Synthetic $label',
            category: 'fixture',
            serial: '%_$label',
            status: 'stored',
            notes: 'Must not change',
          ),
        );
        final query = AssetSavedFilterQuery.fromJson({
          'q': '%_$label',
          'status': 'stored',
          'category': 'fixture',
          'sort': 'checked_asc',
          'locationMode': 'exact',
          'location': 'Room %_$label',
          'warranty': 'expired',
          'asOf': '2024-02-29',
          'checkMode': 'on_or_after',
          'checkBefore': '',
          'checkOnOrAfter': '2024-03-01',
        });
        final saved = await api.createSavedFilter('Restart $label', query);
        final assets = await api.list(query: '', status: '', offset: 0);
        check(
          assets.items.length == 1 &&
              (await api.listSavedFilters()).length == 1,
        );
        owners.add({
          'email': email,
          'password': password,
          'accountId': api.account!.id,
          'saved': savedRestartSnapshot(saved),
          'asset': _assetSnapshot(assets.items.single),
        });
      }
      await writeNew(
        file,
        jsonEncode({
          'fixtureId': args[2],
          'endpoint': endpoint.toString(),
          'owners': owners,
        }),
      );
    } else {
      final data =
          jsonDecode(await readBounded(file, 32768)) as Map<String, dynamic>;
      check(
        data.length == 3 &&
            data['fixtureId'] == args[2] &&
            data['endpoint'] == endpoint.toString(),
      );
      final owners = data['owners'] as List<dynamic>;
      check(
        owners.length == 2 && owners[0]['accountId'] != owners[1]['accountId'],
      );
      for (final raw in owners) {
        final owner = raw as Map<String, dynamic>;
        final api = AssetApi(endpoint);
        clients.add(api);
        await api.login(owner['email'] as String, owner['password'] as String);
        check(api.account!.id == owner['accountId']);
        final saved = (await api.listSavedFilters()).single;
        check(
          jsonEncode(savedRestartSnapshot(saved)) == jsonEncode(owner['saved']),
        );
        final assets = await api.list(query: '', status: '', offset: 0);
        check(
          assets.items.length == 1 &&
              jsonEncode(_assetSnapshot(assets.items.single)) ==
                  jsonEncode(owner['asset']),
        );
      }
    }
    stdout.writeln(
      jsonEncode({
        'status': 'completed',
        'stage': stage,
        'syntheticOnly': true,
        'owners': 2,
      }),
    );
  } catch (_) {
    stdout.writeln(jsonEncode({'status': 'failed'}));
    exitCode = 1;
  } finally {
    probe.close(force: true);
    for (final api in clients) {
      api.close();
    }
  }
}

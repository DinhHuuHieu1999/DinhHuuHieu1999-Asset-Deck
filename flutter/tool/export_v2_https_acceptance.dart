import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../lib/api/asset.dart';
import '../lib/api/asset_dates.dart';
import '../lib/api/asset_store.dart';
import '../lib/api/asset_api.dart';
import 'client_https_acceptance.dart' show check, validateDriverArgs;
import 'native_https_seed.dart' show verifyNativeMarker;
import 'export_https_acceptance.dart' show pythonDigest, validatePython;

/// Real authenticated v2 client against a marker-bound synthetic TLS fixture.
Future<void> main(List<String> args) async {
  final clients = <AssetApi>[];
  final probe = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  var stage = 'arguments';
  try {
    check(args.length == 4);
    final endpoint = validateDriverArgs(args.sublist(0, 3));
    validatePython(args[3]);
    stage = 'marker';
    await verifyNativeMarker(probe, endpoint, args[2]);
    final suffix = List.generate(
      12,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final a = AssetApi(endpoint), b = AssetApi(endpoint);
    clients.addAll([a, b]);
    stage = 'registration';
    for (final entry in [('a', a), ('b', b)]) {
      await entry.$2.register(
        email: '${entry.$1}$suffix@example.invalid',
        username: '${entry.$1}$suffix',
        name: 'Synthetic v2 owner',
        password: 'Synthetic-$suffix-42!',
      );
    }
    Future<String> digest(Uint8List bytes) => pythonDigest(args[3], bytes);
    stage = 'empty';
    check((await a.exportInventoryV2(digest: digest)).count == 0);
    stage = 'create';
    AssetRecord? first;
    for (var i = 0; i < 51; i++) {
      final row = await a.create(
        AssetInput(
          name: 'Synthetic export v2 $i',
          category: 'fixture',
          serial: 'SERIAL-%_$i',
          status: 'stored',
          notes: 'Unicode \u4e2d \u{1f680}',
        ),
      );
      first ??= row;
    }
    final other = await b.create(
      const AssetInput(
        name: 'Other owner private',
        category: 'fixture',
        status: 'stored',
      ),
    );
    stage = 'date-update';
    final dated = await a.updateDates(
      await a.readDates(first!.id),
      const AssetDatesInput(
        purchasedOn: '0001-01-01',
        warrantyExpiresOn: '9999-12-31',
      ),
    );
    stage = 'export-v2';
    final snapshot = await a.exportInventoryV2(digest: digest);
    check(
      snapshot.count == 51 &&
          snapshot.records.map((r) => r.asset.id).toSet().length == 51,
    );
    final exported = snapshot.records.singleWhere(
      (r) => r.asset.id == first!.id,
    );
    check(
      exported.asset.version == dated.version &&
          exported.dates.purchasedOn == '0001-01-01' &&
          exported.dates.warrantyExpiresOn == '9999-12-31',
    );
    check(
      snapshot.records
          .where((r) => r.asset.id != first!.id)
          .every(
            (r) =>
                r.dates.purchasedOn == null &&
                r.dates.warrantyExpiresOn == null,
          ),
    );
    check(
      snapshot.records.every(
        (r) => r.asset.input.notes == 'Unicode \u4e2d \u{1f680}',
      ),
    );
    stage = 'owner-isolation';
    check(!snapshot.records.any((r) => r.asset.id == other.id));
    final otherSnapshot = await b.exportInventoryV2(digest: digest);
    check(
      otherSnapshot.count == 1 &&
          otherSnapshot.records.single.asset.id == other.id,
    );
    stage = 'v1-preservation';
    final v1 = await a.exportInventory(digest: digest);
    check(v1.count == 51);
    final v1Payload = jsonDecode(
      (jsonDecode(v1.json) as Map<String, dynamic>)['payload'] as String,
    ) as Map<String, dynamic>;
    check(
      (v1Payload['records'] as List).every(
        (r) =>
            !(r as Map).containsKey('purchasedOn') &&
            !r.containsKey('warrantyExpiresOn'),
      ),
    );
    stage = 'filter-independence';
    check(
      (await a.list(
        query: 'missing',
        status: 'retired',
        category: 'absent',
        offset: 0,
      )).items.isEmpty,
    );
    final again = await a.exportInventoryV2(digest: digest);
    check(again.count == 51);
    String rows(String json) => jsonEncode(
      (jsonDecode(
        (jsonDecode(json) as Map<String, dynamic>)['payload'] as String,
      ) as Map<String, dynamic>)['records'],
    );
    stage = 'read-only';
    check(rows(again.json) == rows(snapshot.json));
    stage = 'sign-out';
    a.signOut();
    var refused = false;
    try {
      await a.exportInventoryV2(
        digest: (_) async => throw StateError('must not run'),
      );
    } on AssetFailure catch (error) {
      refused = error.statusCode == 401;
    }
    check(refused);
    stdout.writeln(
      jsonEncode({
        'status': 'completed',
        'syntheticOnly': true,
        'exportV2Acceptance': true,
        'owners': 2,
        'assetCount': 51,
        'digest': 'python-sha256-stdin',
        'nativeDialog': 'not-exercised',
      }),
    );
  } catch (_) {
    stderr.writeln(
      'Synthetic export v2 HTTPS failed at $stage; no automatic retry.',
    );
    if (stage == 'arguments') {
      exitCode = 1;
    } else {
      stdout.writeln(jsonEncode({'status': 'failed', 'stage': stage}));
    }
  } finally {
    probe.close(force: true);
    for (final client in clients) {
      client.close();
    }
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../lib/api/asset.dart';
import '../lib/api/asset_api.dart';
import '../lib/api/asset_store.dart';
import 'client_https_acceptance.dart' show check, validateDriverArgs;
import 'native_https_seed.dart' show verifyNativeMarker;

/// Capture every bounded page, including metadata, to detect unintended writes.
Future<String> serialInventorySnapshot(AssetStore api) async {
  final rows = <Object?>[];
  var offset = 0;
  while (true) {
    final page = await api.list(query: '', status: '', offset: offset);
    rows.addAll(
      page.items.map(
        (r) => {
          'id': r.id,
          'version': r.version,
          'input': r.input.toJson(),
          'createdAt': r.createdAt.toIso8601String(),
          'updatedAt': r.updatedAt.toIso8601String(),
        },
      ),
    );
    if (page.nextOffset == null) break;
    check(page.nextOffset! > offset && page.nextOffset! <= 100);
    offset = page.nextOffset!;
  }
  return jsonEncode(rows);
}

/// Real-client synthetic acceptance; never changes TLS trust or retries a write.
Future<void> main(List<String> args) async {
  final probe = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final clients = <AssetApi>[];
  var stage = 'arguments';
  try {
    final endpoint = validateDriverArgs(args);
    stage = 'marker';
    await verifyNativeMarker(probe, endpoint, args[2]);
    final suffix = List.generate(
      10,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final a = AssetApi(endpoint), b = AssetApi(endpoint);
    clients.addAll([a, b]);
    stage = 'registration';
    for (final entry in [(a, 'a'), (b, 'b')]) {
      await entry.$1.register(
        email: '${entry.$2}$suffix@example.invalid',
        username: '${entry.$2}$suffix',
        name: 'Synthetic serial owner',
        password: 'Synthetic-$suffix-42!',
      );
    }
    stage = 'seed';
    const input = AssetInput(
      name: 'Serial target',
      category: 'fixture',
      serial: 'AbC%_1',
      status: 'stored',
    );
    final own = await a.create(input);
    final foreign = await b.create(
      const AssetInput(
        name: 'Foreign serial',
        category: 'fixture',
        serial: 'Foreign-only',
        status: 'stored',
      ),
    );
    stage = 'owned-read';
    final beforeA = await serialInventorySnapshot(a);
    final beforeB = await serialInventorySnapshot(b);
    check((await a.readAsset(own.id)).id == own.id);
    stage = 'owner-isolation';
    for (final pair in [(a, foreign.id), (b, own.id)]) {
      var refused = false;
      try { await pair.$1.readAsset(pair.$2); } catch (_) { refused = true; }
      check(refused);
    }
    check(await serialInventorySnapshot(a) == beforeA);
    check(await serialInventorySnapshot(b) == beforeB);
    stage = 'fresh-version';
    final updated = await a.update(own, const AssetInput(
      name: 'Refreshed asset', category: 'fixture', serial: 'AbC%_1', status: 'stored', notes: 'Refreshed details'));
    final refreshed = await a.readAsset(own.id);
    check(refreshed.version == updated.version);
    check(refreshed.input.notes == 'Refreshed details');
    stdout.writeln(
      jsonEncode({
        'status': 'completed',
        'syntheticOnly': true,
        'detailsAcceptance': true,
        'owners': 2,
        'readOnlySnapshots': 2,
      }),
    );
  } catch (_) {
    stdout.writeln(jsonEncode({'status': 'failed', 'stage': stage}));
    exitCode = 1;
  } finally {
    probe.close(force: true);
    for (final client in clients) {
      client.close();
    }
  }
}

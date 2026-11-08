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
    for (var i = 0; i < 51; i++) {
      await a.create(
        AssetInput(
          name: 'Filler $i',
          category: 'fixture',
          serial: 'filler-$i',
          status: 'stored',
        ),
      );
    }
    check(
      !(await a.list(
        query: '',
        status: '',
        offset: 0,
      )).items.any((r) => r.id == own.id),
    );
    final beforeA = await serialInventorySnapshot(a);
    final beforeB = await serialInventorySnapshot(b);
    stage = 'serial-reads';
    check(await a.serialDuplicate(' AbC%_1 '));
    for (final value in [
      'abc%_1',
      '%',
      '_',
      '',
      "' OR 1=1 --",
      'Foreign-only',
    ]) {
      check(!await a.serialDuplicate(value));
    }
    check(!await a.serialDuplicate('AbC%_1', excludeId: own.id));
    check(await a.serialDuplicate('AbC%_1', excludeId: foreign.id));
    check(!await b.serialDuplicate('AbC%_1'));
    check(await b.serialDuplicate('Foreign-only'));
    check(await serialInventorySnapshot(a) == beforeA);
    check(await serialInventorySnapshot(b) == beforeB);
    stage = 'duplicates-allowed';
    final duplicate = await a.create(input);
    final updated = await a.update(duplicate, input);
    check(updated.version == duplicate.version + 1);
    check(await a.serialDuplicate('AbC%_1', excludeId: own.id));
    stdout.writeln(
      jsonEncode({
        'status': 'completed',
        'syntheticOnly': true,
        'serialAcceptance': true,
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

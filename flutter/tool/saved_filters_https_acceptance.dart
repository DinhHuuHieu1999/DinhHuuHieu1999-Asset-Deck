import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../lib/api/asset_api.dart';
import '../lib/api/asset_saved_filter.dart';
import '../lib/api/asset_store.dart';
import 'client_https_acceptance.dart' show check, validateDriverArgs;
import 'native_https_seed.dart' show verifyNativeMarker;

/// Require a complete saved-definition round trip, not merely a success status.
void verifySavedDefinition(
  AssetSavedFilter saved,
  String name,
  AssetSavedFilterQuery query,
  int version,
) {
  check(saved.name == name && saved.version == version);
  check(
    query.values.entries.every((e) => saved.query.values[e.key] == e.value),
  );
}

/// Marker-bound real-client acceptance; never disable TLS checks or retry writes.
Future<void> main(List<String> args) async {
  final clients = <AssetApi>[];
  final probe = HttpClient()..connectionTimeout = const Duration(seconds: 10);
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
        name: 'Synthetic saved-filter owner',
        password: 'Synthetic-$suffix-42!',
      );
    }
    final query = AssetSavedFilterQuery.fromJson({
      'q': '%_',
      'status': 'stored',
      'category': 'fixture',
      'sort': 'checked_asc',
      'locationMode': 'exact',
      'location': 'Room %_1',
      'warranty': 'expired',
      'asOf': '2024-02-29',
      'checkMode': 'on_or_after',
      'checkBefore': '',
      'checkOnOrAfter': '2024-03-01',
    });
    stage = 'create';
    final saved = await a.createSavedFilter('Literal view', query);
    verifySavedDefinition(saved, 'Literal view', query, 1);
    stage = 'isolation';
    check((await b.listSavedFilters()).isEmpty);
    try {
      await b.deleteSavedFilter(saved);
      throw StateError('Foreign deletion unexpectedly succeeded');
    } on AssetFailure catch (error) {
      check(error.statusCode == 404);
    }
    verifySavedDefinition(
      (await a.listSavedFilters()).single,
      'Literal view',
      query,
      1,
    );
    stage = 'rename';
    final renamed = await a.updateSavedFilter(saved, 'Renamed view', query);
    verifySavedDefinition(renamed, 'Renamed view', query, 2);
    stage = 'stale';
    try {
      await a.deleteSavedFilter(saved);
      throw StateError('Stale deletion unexpectedly succeeded');
    } on AssetFailure catch (error) {
      check(error.statusCode == 409);
    }
    stage = 'delete';
    await a.deleteSavedFilter(renamed);
    check((await a.listSavedFilters()).isEmpty);
    check((await b.listSavedFilters()).isEmpty);
    stdout.writeln(
      jsonEncode({
        'status': 'completed',
        'syntheticOnly': true,
        'savedFiltersAcceptance': true,
        'owners': 2,
        'mutations': 3,
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

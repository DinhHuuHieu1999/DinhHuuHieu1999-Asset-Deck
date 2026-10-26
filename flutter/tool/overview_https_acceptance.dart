import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../lib/api/asset.dart';
import '../lib/api/asset_api.dart';
import 'client_https_acceptance.dart'
    show check, validateDriverArgs, validateMarker;

/// Marker-bound synthetic overview acceptance; never disables TLS verification.
Future<void> main(List<String> args) async {
  final clients = <AssetApi>[];
  final probe = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  var stage = 'arguments';
  try {
    final endpoint = validateDriverArgs(args);
    stage = 'marker';
    final request = await probe.getUrl(
      endpoint.replace(path: '/__asset_desk_fixture/${args[2]}'),
    );
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 10));
    check(response.statusCode == 200);
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 10))) {
      bytes.addAll(chunk);
      check(bytes.length <= 1024);
    }
    validateMarker(jsonDecode(utf8.decode(bytes)), args[2]);
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
        name: 'Synthetic overview owner',
        password: 'Synthetic-$suffix-42!',
      );
    }
    stage = 'empty-overview';
    final empty = await a.overview();
    check(
      empty.total == 0 &&
          empty.byCategory.isEmpty &&
          empty.byStatus.values.every((v) => v == 0),
    );
    const input = AssetInput(
      name: 'Synthetic overview router',
      category: 'network',
      status: 'stored',
    );
    stage = 'seed';
    for (var i = 0; i < 51; i++) {
      await a.create(input);
    }
    final updated = await a.create(
      const AssetInput(
        name: 'Synthetic repair',
        category: 'Network',
        status: 'repair',
      ),
    );
    await a.create(
      const AssetInput(
        name: 'Synthetic Unicode',
        category: '%_\u6a5f\u5668',
        status: 'retired',
      ),
    );
    await b.create(
      const AssetInput(
        name: 'Synthetic second owner',
        category: 'network',
        status: 'in_use',
      ),
    );
    stage = 'list';
    final filtered = await a.list(
      query: '',
      status: 'stored',
      category: 'network',
      offset: 0,
    );
    check(filtered.items.length == 50 && filtered.nextOffset == 50);
    stage = 'complete-overview';
    final overview = await a.overview();
    check(overview.total == 53);
    check(
      overview.byStatus['stored'] == 51 &&
          overview.byStatus['repair'] == 1 &&
          overview.byStatus['retired'] == 1 &&
          overview.byStatus['in_use'] == 0,
    );
    check(
      overview.byCategory.length == 3 &&
          overview.byCategory['network'] == 51 &&
          overview.byCategory['Network'] == 1 &&
          overview.byCategory['%_\u6a5f\u5668'] == 1,
    );
    stage = 'other-owner';
    final theirs = await b.overview();
    check(
      theirs.total == 1 &&
          theirs.byStatus['in_use'] == 1 &&
          theirs.byCategory['network'] == 1,
    );
    Future<String> records() async {
      final values = <Object?>[];
      for (final offset in [0, 50]) {
        final page = await a.list(query: '', status: '', offset: offset);
        for (final row in page.items) {
          values.add([
            row.id,
            row.version,
            row.input.toJson(),
            row.createdAt.toIso8601String(),
            row.updatedAt.toIso8601String(),
          ]);
        }
      }
      check(values.length == 53);
      return jsonEncode(values);
    }

    stage = 'read-only-record-comparison';
    final before = await records();
    await a.overview();
    check(before == await records());
    stage = 'update';
    await a.update(
      updated,
      const AssetInput(
        name: 'Synthetic repair',
        category: 'network',
        status: 'stored',
      ),
    );
    stage = 'updated-overview';
    final refreshed = await a.overview();
    check(
      refreshed.total == 53 &&
          refreshed.byStatus['stored'] == 52 &&
          refreshed.byStatus['repair'] == 0 &&
          refreshed.byCategory['network'] == 52 &&
          !refreshed.byCategory.containsKey('Network'),
    );
    check((await b.overview()).total == 1);
    stage = 'sign-out';
    a.signOut();
    var refused = false;
    try {
      await a.overview();
    } catch (_) {
      refused = true;
    }
    check(refused);
    stdout.writeln(
      jsonEncode({
        'status': 'completed',
        'syntheticOnly': true,
        'overviewAcceptance': true,
        'owners': 2,
        'records': 53,
      }),
    );
  } catch (_) {
    stderr.writeln(
      'Overview HTTPS acceptance failed at $stage; no automatic retry.',
    );
    if (stage == 'arguments') {
      exitCode = 1;
    } else {
      stdout.writeln(jsonEncode({'status': 'failed', 'stage': stage}));
    }
  } finally {
    for (final client in clients) {
      client.close();
    }
    probe.close(force: true);
  }
}

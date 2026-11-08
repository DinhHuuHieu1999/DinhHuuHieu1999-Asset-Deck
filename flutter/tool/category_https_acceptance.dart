import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../lib/api/asset.dart';
import '../lib/api/asset_api.dart';
import 'client_https_acceptance.dart'
    show check, validateDriverArgs, validateMarker;

/// Marker-bound synthetic category acceptance; never disables TLS verification.
Future<void> main(List<String> args) async {
  final clients = <AssetApi>[];
  final probe = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final endpoint = validateDriverArgs(args);
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
    for (final entry in [(a, 'a'), (b, 'b')]) {
      await entry.$1.register(
        email: '${entry.$2}$suffix@example.invalid',
        username: '${entry.$2}$suffix',
        name: 'Synthetic category owner',
        password: 'Synthetic-$suffix-42!',
      );
    }
    const input = AssetInput(
      name: 'Synthetic %_ router',
      category: 'network',
      status: 'stored',
    );
    for (var i = 0; i < 51; i++) {
      await a.create(input);
    }
    final other = await b.create(input);
    for (final category in ['Network', "%_' OR true --", 'Thi?t b?']) {
      await a.create(
        AssetInput(name: input.name, category: category, status: 'stored'),
      );
    }
    await a.create(
      const AssetInput(
        name: 'Synthetic %_ router',
        category: 'network',
        status: 'repair',
      ),
    );
    final first = await a.list(
      query: '%_',
      status: 'stored',
      category: ' network ',
      offset: 0,
    );
    final second = await a.list(
      query: '%_',
      status: 'stored',
      category: 'network',
      offset: 50,
    );
    check(first.items.length == 50 && first.nextOffset == 50);
    check(second.items.length == 1 && second.nextOffset == null);
    final ids = {
      ...first.items.map((r) => r.id),
      ...second.items.map((r) => r.id),
    };
    check(ids.length == 51 && !ids.contains(other.id));
    for (final category in ['Network', "%_' OR true --", 'Thi?t b?']) {
      final page = await a.list(
        query: '%_',
        status: 'stored',
        category: category,
        offset: 0,
      );
      check(
        page.items.length == 1 && page.items.single.input.category == category,
      );
    }
    check(
      (await a.list(
        query: '',
        status: '',
        category: 'NETWORK',
        offset: 0,
      )).items.isEmpty,
    );
    check(
      (await a.list(
            query: '',
            status: 'repair',
            category: 'network',
            offset: 0,
          )).items.length ==
          1,
    );
    check(
      (await b.list(
            query: '',
            status: '',
            category: 'network',
            offset: 0,
          )).items.single.id ==
          other.id,
    );
    check((await a.list(query: '', status: '', offset: 0)).nextOffset == 50);
    stdout.writeln(
      jsonEncode({
        'status': 'completed',
        'syntheticOnly': true,
        'categoryAcceptance': true,
        'owners': 2,
        'matchingRecords': 51,
      }),
    );
  } catch (_) {
    stderr.writeln('Synthetic category acceptance failed; no automatic retry');
    exitCode = 1;
  } finally {
    probe.close(force: true);
    for (final client in clients) {
      client.close();
    }
  }
}

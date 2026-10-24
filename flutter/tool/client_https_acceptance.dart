import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../lib/api/asset.dart';
import '../lib/api/asset_api.dart';
import '../lib/api/asset_store.dart';

void check(bool value) {
  if (!value) throw StateError('Synthetic acceptance check failed');
}

Future<void> conflict(Future<Object?> Function() action) async {
  try {
    await action();
  } on AssetFailure catch (error) {
    check(error.statusCode == 409);
    return;
  }
  throw StateError('Expected conflict');
}

/// Reject non-fixture targets before any registration or client writes.
Uri validateDriverArgs(List<String> args) {
  check(args.length == 3 && args[0] == '--synthetic-only');
  final endpoint = Uri.parse(args[1]);
  check(
    endpoint.scheme == 'https' &&
        endpoint.host == 'localhost' &&
        endpoint.path == '/api/v1' &&
        endpoint.port >= 1024 &&
        endpoint.port <= 65535 &&
        ![8180, 8443, 28443].contains(endpoint.port) &&
        endpoint.userInfo.isEmpty &&
        !endpoint.hasQuery &&
        !endpoint.hasFragment &&
        RegExp(r'^[a-f0-9]{32}$').hasMatch(args[2]),
  );
  return endpoint;
}

/// Exact random marker is mandatory; a health response is not fixture ownership.
void validateMarker(Object? marker, String fixtureId) {
  check(
    marker is Map &&
        marker['fixtureId'] == fixtureId &&
        marker['syntheticOnly'] == true,
  );
}

/// Actual client acceptance; requires explicit opt-in and a matching TLS marker.
Future<void> main(List<String> args) async {
  if (args.length != 3 || args[0] != '--synthetic-only') {
    stderr.writeln('Explicit synthetic endpoint and fixture identity required');
    exitCode = 2;
    return;
  }
  final clients = <AssetApi>[];
  final probe = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final endpoint = validateDriverArgs(args);
    final fixtureId = args[2];
    // Default trust and hostname validation: never install a certificate callback.
    final request = await probe
        .getUrl(endpoint.replace(path: '/__asset_desk_fixture/$fixtureId'))
        .timeout(const Duration(seconds: 10));
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 10));
    check(response.statusCode == 200);
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 10))) {
      bytes.addAll(chunk);
      check(bytes.length <= 1024);
    }
    final marker = jsonDecode(utf8.decode(bytes));
    validateMarker(marker, fixtureId);
    AssetApi client() {
      final result = AssetApi(endpoint);
      clients.add(result);
      return result;
    }

    final random = Random.secure();
    final suffix = List.generate(
      12,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final password = 'Synthetic-$suffix-42!';
    final a = client(), b = client();
    final email = 'a$suffix@example.invalid';
    await a.register(
      email: email,
      username: 'a$suffix',
      name: 'Synthetic A',
      password: password,
    );
    await b.register(
      email: 'b$suffix@example.invalid',
      username: 'b$suffix',
      name: 'Synthetic B',
      password: password,
    );
    const target = AssetInput(
      name: 'Synthetic asset %_',
      category: 'fixture',
      status: 'stored',
    );
    final original = await a.create(target);
    for (var i = 0; i < 50; i++) {
      await a.create(
        AssetInput(
          name: 'Synthetic filler $i',
          category: 'fixture',
          status: 'in_use',
        ),
      );
    }
    check(
      (await a.list(query: '%_', status: 'stored', offset: 0)).items.length ==
          1,
    );
    check(
      (await a.list(query: '%_', status: 'repair', offset: 0)).items.isEmpty,
    );
    final first = await a.list(query: '', status: '', offset: 0);
    check(first.items.length == 50 && first.nextOffset == 50);
    final second = await a.list(query: '', status: '', offset: 50);
    check(second.items.length == 1 && second.nextOffset == null);
    check(
      {
            ...first.items.map((v) => v.id),
            ...second.items.map((v) => v.id),
          }.length ==
          51,
    );
    check((await b.list(query: '', status: '', offset: 0)).items.isEmpty);
    await conflict(() => b.update(original, target));
    const edited = AssetInput(
      name: 'Synthetic edited %_',
      category: 'fixture',
      status: 'stored',
    );
    check((await a.update(original, edited)).version == 2);
    await conflict(() => a.update(original, target));
    a.signOut();
    final fresh = client();
    await fresh.login(email, password);
    final saved = await fresh.list(query: '%_', status: 'stored', offset: 0);
    check(
      saved.items.length == 1 &&
          saved.items.single.version == 2 &&
          saved.items.single.input.name == edited.name,
    );
    stdout.writeln(
      jsonEncode({
        'status': 'completed',
        'syntheticOnly': true,
        'assetCount': 51,
        'owners': 2,
      }),
    );
  } catch (_) {
    // Do not emit credentials, tokens, URLs, exception bodies or server responses.
    stderr.writeln('Synthetic client acceptance failed; no automatic retry');
    exitCode = 1;
  } finally {
    probe.close(force: true);
    for (final client in clients) {
      client.close();
    }
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../lib/api/asset.dart';
import '../lib/api/asset_api.dart';
import 'client_https_acceptance.dart' show validateDriverArgs, validateMarker;

/// Check the bounded marker response before creating any authenticated API client.
Future<void> verifyNativeMarker(
  HttpClient probe,
  Uri endpoint,
  String fixtureId,
) async {
  final request = await probe
      .getUrl(endpoint.replace(path: '/__asset_desk_fixture/$fixtureId'))
      .timeout(const Duration(seconds: 10));
  request.followRedirects = false;
  final response = await request.close().timeout(const Duration(seconds: 10));
  if (response.statusCode != 200) throw StateError('Fixture marker missing');
  final bytes = <int>[];
  await for (final chunk in response.timeout(const Duration(seconds: 10))) {
    bytes.addAll(chunk);
    if (bytes.length > 1024) throw StateError('Marker exceeds limit');
  }
  validateMarker(jsonDecode(utf8.decode(bytes)), fixtureId);
}

/// Seed only a TLS-validated, randomly identified synthetic fixture.
Future<void> main(List<String> args) async {
  AssetApi? api;
  final probe = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final endpoint = validateDriverArgs(args);
    await verifyNativeMarker(probe, endpoint, args[2]);
    final random = Random.secure();
    final suffix = List.generate(
      12,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final username = 'n$suffix';
    final password = 'Synthetic-$suffix-42!';
    api = AssetApi(endpoint);
    await api.register(
      email: '$username@example.invalid',
      username: username,
      name: 'Synthetic native operator',
      password: password,
    );
    await api.create(
      const AssetInput(
        name: 'Synthetic native asset',
        category: 'fixture',
        serial: 'NATIVE-%_1',
        status: 'stored',
        notes: 'Synthetic data only; manual Windows acceptance is pending.',
      ),
    );
    stdout.writeln(
      jsonEncode({
        'username': username,
        'password': password,
        'assetName': 'Synthetic native asset',
      }),
    );
  } catch (_) {
    stderr.writeln('Native seed failed or refused; no automatic retry.');
    exitCode = 1;
  } finally {
    api?.close();
    probe.close(force: true);
  }
}

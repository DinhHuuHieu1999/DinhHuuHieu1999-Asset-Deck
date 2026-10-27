import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../lib/api/asset.dart';
import '../lib/api/asset_api.dart';
import '../lib/api/asset_dates.dart';
import 'client_https_acceptance.dart' show validateDriverArgs;
import 'native_https_seed.dart' show verifyNativeMarker;

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
    final asset = await api.create(
      const AssetInput(
        name: 'Synthetic native asset',
        category: 'fixture',
        serial: 'NATIVE-%_1',
        status: 'stored',
        notes: 'Synthetic data only; manual Windows acceptance is pending.',
      ),
    );
    await api.updateDates(
      await api.readDates(asset.id),
      const AssetDatesInput(
        purchasedOn: '2024-02-29',
        warrantyExpiresOn: '2027-02-28',
      ),
    );
    await api.updateLocation(
      await api.readLocation(asset.id),
      'Synthetic room %_1',
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

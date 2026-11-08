import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../lib/api/asset.dart';
import '../lib/api/asset_dates.dart';
import '../lib/api/asset_store.dart';
import '../lib/api/asset_api.dart';
import 'client_https_acceptance.dart'
    show check, validateDriverArgs, validateMarker;

/// Marker-bound synthetic dates acceptance; never disables TLS verification.
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
        name: 'Synthetic dates owner',
        password: 'Synthetic-$suffix-42!',
      );
    }
    const input = AssetInput(
      name: 'Synthetic dated router',
      category: 'network',
      status: 'stored',
    );
    stage = 'create';
    final row = await a.create(input);
    final other = await b.create(input);
    stage = 'empty-dates';
    final original = await a.readDates(row.id);
    check(
      original.version == row.version &&
          original.input.purchasedOn == null &&
          original.input.warrantyExpiresOn == null,
    );
    stage = 'date-update';
    final changed = await a.updateDates(
      original,
      const AssetDatesInput(
        purchasedOn: '2000-02-29',
        warrantyExpiresOn: '2030-01-01',
      ),
    );
    check(changed.version == original.version + 1);
    check((await a.readDates(row.id)).input.purchasedOn == '2000-02-29');
    stage = 'owner-isolation';
    Future<void> refused(
      Future<Object?> Function() operation,
      int status,
    ) async {
      try {
        await operation();
      } on AssetFailure catch (error) {
        check(error.statusCode == status);
        return;
      }
      throw StateError('Expected refusal');
    }

    await refused(() => b.readDates(row.id), 404);
    await refused(
      () => b.updateDates(
        changed,
        const AssetDatesInput(purchasedOn: null, warrantyExpiresOn: null),
      ),
      409,
    );
    check((await b.readDates(other.id)).version == other.version);
    stage = 'stale-version';
    await refused(
      () => a.updateDates(
        original,
        const AssetDatesInput(purchasedOn: null, warrantyExpiresOn: null),
      ),
      409,
    );
    stage = 'legacy-preservation';
    final listed = (await a.list(
      query: '',
      status: '',
      offset: 0,
    )).items.single;
    check(
      listed.input.name == input.name &&
          listed.input.category == input.category &&
          listed.input.status == input.status,
    );
    final edited = await a.update(
      listed,
      const AssetInput(
        name: 'Edited legacy asset',
        category: 'network',
        status: 'repair',
      ),
    );
    final preserved = await a.readDates(row.id);
    check(
      preserved.version == edited.version &&
          preserved.input.purchasedOn == '2000-02-29' &&
          preserved.input.warrantyExpiresOn == '2030-01-01',
    );
    stage = 'clear';
    final cleared = await a.updateDates(
      preserved,
      const AssetDatesInput(purchasedOn: null, warrantyExpiresOn: null),
    );
    final reread = await a.readDates(row.id);
    check(
      reread.version == cleared.version &&
          reread.input.purchasedOn == null &&
          reread.input.warrantyExpiresOn == null,
    );
    check(
      (await a.list(
            query: '',
            status: '',
            offset: 0,
          )).items.single.input.name ==
          'Edited legacy asset',
    );
    stage = 'sign-out';
    a.signOut();
    await refused(() => a.readDates(row.id), 401);
    stdout.writeln(
      jsonEncode({
        'status': 'completed',
        'syntheticOnly': true,
        'datesAcceptance': true,
        'owners': 2,
        'records': 2,
      }),
    );
  } catch (_) {
    stderr.writeln(
      'Dates HTTPS acceptance failed at $stage; no automatic retry.',
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

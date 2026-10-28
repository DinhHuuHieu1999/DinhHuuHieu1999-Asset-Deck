import '../lib/api/asset_warranty_overview.dart';

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
import 'warranty_https_acceptance.dart' show rawRequest;

/// Real client and middleware checks only after an exact synthetic TLS marker.
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
    stage = 'anonymous';
    check(
      (await rawRequest(
            probe,
            endpoint,
            'GET',
            'assets/warranty/overview',
          )).$1 ==
          401,
    );
    final suffix = List.generate(
      12,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final password = 'Synthetic-$suffix-42!';
    final a = AssetApi(endpoint), b = AssetApi(endpoint);
    clients.addAll([a, b]);
    stage = 'registration';
    for (final entry in [('a', a), ('b', b)]) {
      await entry.$2.register(
        email: '${entry.$1}$suffix@example.invalid',
        username: '${entry.$1}$suffix',
        name: 'Synthetic warranty owner',
        password: password,
      );
    }
    Future<String> digest(Uint8List bytes) => pythonDigest(args[3], bytes);
    stage = 'empty';
    check((await a.warrantyOverview(asOf: '2026-10-26')).total == 0);
    Future<AssetRecord> seed(
      AssetApi api,
      String name,
      String? end, {
      String category = 'fixture',
      String status = 'stored',
    }) async {
      final row = await api.create(
        AssetInput(
          name: name,
          category: category,
          status: status,
          serial: 'SERIAL-%_',
          notes: 'Synthetic only',
        ),
      );
      if (end != null) {
        await api.updateDates(
          AssetDates(
            id: row.id,
            version: row.version,
            input: const AssetDatesInput(
              purchasedOn: null,
              warrantyExpiresOn: null,
            ),
          ),
          AssetDatesInput(purchasedOn: null, warrantyExpiresOn: end),
        );
      }
      return row;
    }

    stage = 'create';
    for (var i = 0; i < 51; i++) {
      await seed(
        a,
        'Synthetic expiry $i',
        '2026-10-25',
        category: i.isEven ? 'fixture' : 'other',
        status: ['in_use', 'stored', 'repair', 'retired'][i % 4],
      );
    }
    await seed(a, 'Today', '2026-10-26');
    await seed(a, 'Horizon', '2026-11-25');
    await seed(a, 'Later', '2026-11-26');
    await seed(a, 'Unknown', null);
    await seed(b, 'Other owner', null);
    stage = 'read-only';
    final before = await a.exportInventoryV2(digest: digest);
    stage = 'overview';
    final counts = await a.warrantyOverview(asOf: '2026-10-26');
    check(counts.asOf == '2026-10-26' && counts.through == '2026-11-25');
    check(
      counts.total == 55 &&
          counts.expired == 51 &&
          counts.expiringSoon == 2 &&
          counts.later == 1 &&
          counts.unknown == 1,
    );
    // Exercise the typed selection and pinned date against real HTTPS transport.
    // Native navigation remains a separate acceptance step.
    stage = 'pagination';
    for (final filter in ['expired', 'expiring_soon']) {
      final selection = WarrantyOverviewSelection(
        warranty: filter,
        asOf: counts.asOf,
      );
      final ids = <String>{};
      var offset = 0;
      while (true) {
        final page = await a.listWarranty(
          query: '',
          status: '',
          offset: offset,
          warranty: selection.warranty,
          asOf: selection.asOf,
        );
        check(page.asOf == counts.asOf && page.through == counts.through);
        for (final item in page.items) {
          check(ids.add(item.asset.id));
        }
        final next = page.nextOffset;
        if (next == null) break;
        check(next > offset && next <= 100);
        offset = next;
      }
      check(
        ids.length ==
            (filter == 'expired' ? counts.expired : counts.expiringSoon),
      );
      final otherPage = await b.listWarranty(
        query: '',
        status: '',
        offset: 0,
        warranty: selection.warranty,
        asOf: selection.asOf,
      );
      check(otherPage.items.isEmpty && otherPage.nextOffset == null);
    }
    final todayUtc = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final fresh = await a.warrantyOverview();
    final afterUtc = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    check(fresh.asOf == todayUtc || fresh.asOf == afterUtc);
    check(fresh.total == 55);
    stage = 'owner-isolation';
    final other = await b.warrantyOverview(asOf: '2026-10-26');
    check(
      other.total == 1 &&
          other.unknown == 1 &&
          other.expired == 0 &&
          other.expiringSoon == 0 &&
          other.later == 0,
    );
    stage = 'validation';
    final csrf = await rawRequest(probe, endpoint, 'GET', 'csrf-token');
    check(csrf.$1 == 200 && csrf.$2['token'] is String && csrf.$3.isNotEmpty);
    final login = await rawRequest(
      probe,
      endpoint,
      'POST',
      'auth/login',
      csrf: csrf.$2['token']! as String,
      cookies: csrf.$3,
      body: {'identifier': 'a$suffix', 'password': password},
    );
    check(login.$1 == 200 && login.$2['accessToken'] is String);
    final token = login.$2['accessToken']! as String;
    for (final query in [
      '?asOf=2026-02-29',
      '?ownerId=foreign',
      '?status=stored',
      '?offset=0',
      '?asOf=2026-10-26&asOf=2026-10-27',
    ]) {
      check(
        (await rawRequest(
              probe,
              endpoint,
              'GET',
              'assets/warranty/overview$query',
              bearer: token,
            )).$1 ==
            400,
      );
    }
    stage = 'read-only';
    final after = await a.exportInventoryV2(digest: digest);
    String rows(String value) => jsonEncode(
      (jsonDecode((jsonDecode(value) as Map)['payload'] as String)
          as Map)['records'],
    );
    check(
      before.count == 55 &&
          after.count == 55 &&
          rows(before.json) == rows(after.json),
    );
    stage = 'sign-out';
    a.signOut();
    var refused = false;
    try {
      await a.warrantyOverview();
    } on AssetFailure catch (error) {
      refused = error.statusCode == 401;
    }
    check(refused);
    stdout.writeln(
      jsonEncode({
        'status': 'completed',
        'syntheticOnly': true,
        'warrantyOverviewAcceptance': true,
        'owners': 2,
        'assetCount': 55,
        'digest': 'python-sha256-stdin',
        'nativeDialog': 'not-exercised',
      }),
    );
  } catch (_) {
    stderr.writeln(
      'Synthetic warranty overview HTTPS failed at $stage; no automatic retry.',
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

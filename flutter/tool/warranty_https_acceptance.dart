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

/// Bounded raw requests exercise middleware, never bypass client validation in production.
Future<(int, Map<String, Object?>, List<Cookie>)> rawRequest(
  HttpClient client,
  Uri endpoint,
  String method,
  String path, {
  String? bearer,
  String? csrf,
  List<Cookie> cookies = const [],
  Map<String, Object?>? body,
}) async {
  final request = await client
      .openUrl(method, Uri.parse('${endpoint.toString()}/$path'))
      .timeout(const Duration(seconds: 10));
  request.followRedirects = false;
  request.headers.set(
    'x-request-timestamp',
    '${DateTime.now().millisecondsSinceEpoch}',
  );
  request.headers.set(HttpHeaders.acceptHeader, 'application/json');
  if (bearer != null)
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
  if (csrf != null) request.headers.set('x-csrf-token', csrf);
  request.cookies.addAll(cookies);
  if (body != null) {
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
  }
  final response = await request.close().timeout(const Duration(seconds: 10));
  final bytes = <int>[];
  await for (final chunk in response.timeout(const Duration(seconds: 10))) {
    bytes.addAll(chunk);
    check(bytes.length <= 65536);
  }
  final decoded = jsonDecode(utf8.decode(bytes));
  check(decoded is Map<String, Object?>);
  return (
    response.statusCode,
    decoded as Map<String, Object?>,
    response.cookies,
  );
}

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
            'assets/warranty?warranty=expired',
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
    check(
      (await a.listWarranty(
        query: '',
        status: '',
        warranty: 'expired',
        asOf: '2026-10-26',
        offset: 0,
      )).items.isEmpty,
    );
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
    final expiredIds = <String>{};
    for (var i = 0; i < 51; i++) {
      expiredIds.add(
        (await seed(a, 'Synthetic warranty %_ $i', '2026-10-25')).id,
      );
    }
    final today = await seed(a, 'Ends today', '2026-10-26');
    final horizon = await seed(a, 'Ends horizon', '2026-11-25');
    await seed(a, 'Ends outside', '2026-11-26');
    await seed(a, 'Unknown warranty', null);
    final foreign = await seed(b, 'Other owner', '2026-10-25');
    stage = 'warranty';
    final upcoming = await a.listWarranty(
      query: '',
      status: '',
      warranty: 'expiring_soon',
      asOf: '2026-10-26',
      offset: 0,
    );
    check(upcoming.asOf == '2026-10-26' && upcoming.through == '2026-11-25');
    check(
      upcoming.items.map((r) => r.asset.id).toSet().difference({
        today.id,
        horizon.id,
      }).isEmpty,
    );
    check(upcoming.items.length == 2);
    final fresh = await a.listWarranty(
      query: '',
      status: '',
      warranty: 'expired',
      offset: 0,
    );
    check(fresh.asOf.length == 10 && fresh.through.length == 10);
    stage = 'pagination';
    final first = await a.listWarranty(
      query: ' WARRANTY %_ ',
      status: 'stored',
      category: ' fixture ',
      warranty: 'expired',
      asOf: '2026-10-26',
      offset: 0,
    );
    check(first.items.length == 50 && first.nextOffset == 50);
    final second = await a.listWarranty(
      query: 'warranty %_',
      status: 'stored',
      category: 'fixture',
      warranty: 'expired',
      asOf: first.asOf,
      offset: first.nextOffset!,
    );
    check(second.items.length == 1 && second.nextOffset == null);
    final all = {
      ...first.items.map((r) => r.asset.id),
      ...second.items.map((r) => r.asset.id),
    };
    check(all.length == 51 && all.difference(expiredIds).isEmpty);
    for (final filters in [
      ('missing', 'stored', 'fixture'),
      ('', 'repair', 'fixture'),
      ('', 'stored', 'FIXTURE'),
      ("' OR 1=1 --", '', ''),
    ]) {
      check(
        (await a.listWarranty(
          query: filters.$1,
          status: filters.$2,
          category: filters.$3,
          warranty: 'expired',
          asOf: first.asOf,
          offset: 0,
        )).items.isEmpty,
      );
    }
    stage = 'owner-isolation';
    final other = await b.listWarranty(
      query: '',
      status: '',
      warranty: 'expired',
      asOf: first.asOf,
      offset: 0,
    );
    check(other.items.length == 1 && other.items.single.asset.id == foreign.id);
    check(!all.contains(foreign.id));
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
    check(token.isNotEmpty && token.length <= 16384);
    for (final query in [
      '',
      '?warranty=all',
      '?warranty=expired&asOf=2026-02-29',
      '?warranty=expired&ownerId=foreign',
      '?warranty=expired&offset=100001',
      '?warranty=expired&warranty=expired',
    ]) {
      check(
        (await rawRequest(
              probe,
              endpoint,
              'GET',
              'assets/warranty$query',
              bearer: token,
            )).$1 ==
            400,
      );
    }
    stage = 'read-only';
    final before = await a.exportInventoryV2(digest: digest);
    final overview = await a.overview();
    await a.listWarranty(
      query: '',
      status: '',
      warranty: 'expired',
      asOf: first.asOf,
      offset: 0,
    );
    final after = await a.exportInventoryV2(digest: digest);
    String rows(String value) => jsonEncode(
      (jsonDecode((jsonDecode(value) as Map)['payload'] as String)
          as Map)['records'],
    );
    check(before.count == 55 && rows(before.json) == rows(after.json));
    final overviewAfter = await a.overview();
    check(
      overviewAfter.total == overview.total &&
          jsonEncode(overviewAfter.byStatus) == jsonEncode(overview.byStatus) &&
          jsonEncode(overviewAfter.byCategory) ==
              jsonEncode(overview.byCategory),
    );
    final v1 = await a.exportInventory(digest: digest);
    check(v1.count == 55);
    stage = 'sign-out';
    a.signOut();
    var refused = false;
    try {
      await a.listWarranty(
        query: '',
        status: '',
        warranty: 'expired',
        offset: 0,
      );
    } on AssetFailure catch (error) {
      refused = error.statusCode == 401;
    }
    check(refused);
    stdout.writeln(
      jsonEncode({
        'status': 'completed',
        'syntheticOnly': true,
        'warrantyAcceptance': true,
        'owners': 2,
        'assetCount': 55,
        'digest': 'python-sha256-stdin',
        'nativeDialog': 'not-exercised',
      }),
    );
  } catch (_) {
    stderr.writeln(
      'Synthetic warranty HTTPS failed at $stage; no automatic retry.',
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

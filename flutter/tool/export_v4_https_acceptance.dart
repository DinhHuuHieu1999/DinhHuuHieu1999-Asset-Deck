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

/// Fail closed on unexpected raw HTTP contract responses; no payload is retained.
void validateExportV4Http(
  int status,
  String? cacheControl, {
  required bool query,
}) {
  check(status == (query ? 400 : 200));
  if (!query)
    check(
      cacheControl
              ?.split(',')
              .map((v) => v.trim().toLowerCase())
              .contains('no-store') ==
          true,
    );
}

/// Test-only login uses synthetic credentials and default TLS verification.
Future<void> verifyExportV4Http(
  HttpClient client,
  Uri endpoint,
  String username,
  String password,
) async {
  Future<HttpClientRequest> request(String method, String path) async {
    final result = await client.openUrl(
      method,
      endpoint.replace(path: '/api/v1/$path'),
    );
    result.followRedirects = false;
    result.headers.set(
      'x-request-timestamp',
      '${DateTime.now().millisecondsSinceEpoch}',
    );
    return result;
  }

  Future<Map<String, dynamic>> object(HttpClientResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 10))) {
      check(bytes.length + chunk.length <= 65536);
      bytes.addAll(chunk);
    }
    final value = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    check(value is Map<String, dynamic>);
    return value as Map<String, dynamic>;
  }

  final csrf = await (await request(
    'GET',
    'csrf-token',
  )).close().timeout(const Duration(seconds: 10));
  check(csrf.statusCode == 200);
  final cookies = csrf.cookies;
  final csrfData = await object(csrf);
  check(csrfData['token'] is String && cookies.isNotEmpty);
  final login = await request('POST', 'auth/login');
  login.cookies.addAll(cookies);
  login.headers.contentType = ContentType.json;
  login.headers.set('x-csrf-token', csrfData['token'] as String);
  login.write(jsonEncode({'identifier': username, 'password': password}));
  final authenticated = await login.close().timeout(
    const Duration(seconds: 10),
  );
  check(authenticated.statusCode == 200);
  final auth = await object(authenticated);
  check(
    auth['accessToken'] is String && (auth['accessToken'] as String).isNotEmpty,
  );
  for (final query in [false, true]) {
    final uri = endpoint.replace(
      path: '/api/v1/assets/export/v4',
      query: query ? 'q=missing' : null,
    );
    final get = await client.getUrl(uri);
    get.followRedirects = false;
    get.headers.set(
      'x-request-timestamp',
      '${DateTime.now().millisecondsSinceEpoch}',
    );
    get.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${auth['accessToken']}',
    );
    final response = await get.close().timeout(const Duration(seconds: 10));
    validateExportV4Http(
      response.statusCode,
      response.headers.value('cache-control'),
      query: query,
    );
    await object(response);
  }
}

/// Real authenticated v4 client against a marker-bound synthetic TLS fixture.
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
    final suffix = List.generate(
      12,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final a = AssetApi(endpoint), b = AssetApi(endpoint);
    clients.addAll([a, b]);
    stage = 'anonymous';
    final anonymousRequest = await probe.getUrl(
      endpoint.replace(path: '/api/v1/assets/export/v4'),
    );
    anonymousRequest.headers.set(
      'x-request-timestamp',
      '${DateTime.now().millisecondsSinceEpoch}',
    );
    final anonymousResponse = await anonymousRequest.close().timeout(
      const Duration(seconds: 10),
    );
    check(anonymousResponse.statusCode == 401);
    await anonymousResponse.drain<void>().timeout(const Duration(seconds: 10));
    stage = 'registration';
    for (final entry in [('a', a), ('b', b)]) {
      await entry.$2.register(
        email: '${entry.$1}$suffix@example.invalid',
        username: '${entry.$1}$suffix',
        name: 'Synthetic v4 owner',
        password: 'Synthetic-$suffix-42!',
      );
    }
    stage = 'http-contract';
    await verifyExportV4Http(
      probe,
      endpoint,
      'a$suffix',
      'Synthetic-$suffix-42!',
    );
    Future<String> digest(Uint8List bytes) => pythonDigest(args[3], bytes);
    stage = 'empty';
    check((await a.exportInventoryV4(digest: digest)).count == 0);
    stage = 'create';
    AssetRecord? first;
    for (var i = 0; i < 51; i++) {
      final row = await a.create(
        AssetInput(
          name: 'Synthetic export v4 $i',
          category: 'fixture',
          serial: 'SERIAL-%_$i',
          status: 'stored',
          notes: 'Unicode \u4e2d \u{1f680}',
        ),
      );
      first ??= row;
    }
    final other = await b.create(
      const AssetInput(
        name: 'Other owner private',
        category: 'fixture',
        status: 'stored',
      ),
    );
    stage = 'date-update';
    final dated = await a.updateDates(
      await a.readDates(first!.id),
      const AssetDatesInput(
        purchasedOn: '0001-01-01',
        warrantyExpiresOn: '9999-12-31',
      ),
    );
    stage = 'location-update';
    final located = await a.updateLocation(
      await a.readLocation(first.id),
      'Room %_1',
    );
    stage = 'check-update';
    final checked = await a.updateCheckDate(
      await a.readCheckDate(first.id),
      '2024-03-01',
    );
    stage = 'export-v4';
    final snapshot = await a.exportInventoryV4(digest: digest);
    check(
      snapshot.count == 51 &&
          snapshot.records.map((r) => r.asset.id).toSet().length == 51,
    );
    final exported = snapshot.records.singleWhere(
      (r) => r.asset.id == first!.id,
    );
    check(
      exported.asset.version == checked.version &&
          checked.version == located.version + 1 &&
          exported.lastCheckedDate == '2024-03-01' &&
          located.version == dated.version + 1 &&
          exported.location == 'Room %_1' &&
          exported.dates.purchasedOn == '0001-01-01' &&
          exported.dates.warrantyExpiresOn == '9999-12-31',
    );
    check(
      snapshot.records
          .where((r) => r.asset.id != first!.id)
          .every(
            (r) =>
                r.location == null &&
                r.lastCheckedDate == null &&
                r.dates.purchasedOn == null &&
                r.dates.warrantyExpiresOn == null,
          ),
    );
    check(
      snapshot.records.every(
        (r) => r.asset.input.notes == 'Unicode \u4e2d \u{1f680}',
      ),
    );
    stage = 'owner-isolation';
    check(!snapshot.records.any((r) => r.asset.id == other.id));
    final otherSnapshot = await b.exportInventoryV4(digest: digest);
    check(
      otherSnapshot.count == 1 &&
          otherSnapshot.records.single.asset.id == other.id,
    );
    stage = 'v1-preservation';
    final v1 = await a.exportInventory(digest: digest);
    check(v1.count == 51);
    final v1Payload = jsonDecode(
      (jsonDecode(v1.json) as Map<String, dynamic>)['payload'] as String,
    ) as Map<String, dynamic>;
    check(
      (v1Payload['records'] as List).every(
        (r) =>
            !(r as Map).containsKey('purchasedOn') &&
            !r.containsKey('warrantyExpiresOn') &&
            !r.containsKey('location'),
      ),
    );
    final v2 = await a.exportInventoryV2(digest: digest);
    final v2Payload =
        jsonDecode((jsonDecode(v2.json) as Map)['payload'] as String) as Map;
    check(
      v2.count == 51 &&
          (v2Payload['records'] as List).every(
            (r) => !(r as Map).containsKey('location'),
          ),
    );
    final v3 = await a.exportInventoryV3(digest: digest);
    final v3Payload =
        jsonDecode((jsonDecode(v3.json) as Map)['payload'] as String) as Map;
    check(
      v3.count == 51 &&
          (v3Payload['records'] as List).every(
            (r) => !(r as Map).containsKey('lastCheckedDate'),
          ),
    );
    stage = 'filter-independence';
    check(
      (await a.list(
        query: 'missing',
        status: 'retired',
        category: 'absent',
        offset: 0,
      )).items.isEmpty,
    );
    final again = await a.exportInventoryV4(digest: digest);
    check(again.count == 51);
    String rows(String json) => jsonEncode(
      (jsonDecode(
        (jsonDecode(json) as Map<String, dynamic>)['payload'] as String,
      ) as Map<String, dynamic>)['records'],
    );
    stage = 'read-only';
    check(rows(again.json) == rows(snapshot.json));
    stage = 'sign-out';
    a.signOut();
    var refused = false;
    try {
      await a.exportInventoryV4(
        digest: (_) async => throw StateError('must not run'),
      );
    } on AssetFailure catch (error) {
      refused = error.statusCode == 401;
    }
    check(refused);
    stdout.writeln(
      jsonEncode({
        'status': 'completed',
        'syntheticOnly': true,
        'exportV4Acceptance': true,
        'owners': 2,
        'assetCount': 51,
        'digest': 'python-sha256-stdin',
        'nativeDialog': 'not-exercised',
      }),
    );
  } catch (_) {
    stderr.writeln(
      'Synthetic export v4 HTTPS failed at $stage; no automatic retry.',
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

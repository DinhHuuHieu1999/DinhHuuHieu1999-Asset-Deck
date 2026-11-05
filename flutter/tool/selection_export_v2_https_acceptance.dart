import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../lib/api/asset.dart';
import '../lib/api/asset_dates.dart';
import '../lib/api/asset_store.dart';
import '../lib/api/asset_selection_export_v2.dart';
import '../lib/api/asset_api.dart';
import 'client_https_acceptance.dart' show check, validateDriverArgs;
import 'native_https_seed.dart' show verifyNativeMarker;
import 'export_https_acceptance.dart' show pythonDigest, validatePython;

/// Fail closed on unexpected raw HTTP contract responses; no payload is retained.
void validateSelectionHttp(
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
Future<void> verifySelectionHttp(
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
  for (final invalid in [
    null,
    'offset=0',
    'unknown=x',
    'checkMode=all&checkMode=unknown',
    'checkMode=before&checkCutoff=2023-02-29',
  ]) {
    final query = invalid != null;
    final uri = endpoint.replace(
      path: '/api/v1/assets/export/selection-v2',
      query: invalid ?? 'checkMode=all',
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
    validateSelectionHttp(
      response.statusCode,
      response.headers.value('cache-control'),
      query: query,
    );
    await object(response);
  }
}

/// Real synthetic client; each completion check follows an asserted response.
Future<void> main(List<String> args) async {
  final clients = <AssetApi>[];
  final probe = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final checks = <String, bool>{};
  var stage = 'arguments';
  try {
    check(args.length == 4);
    final endpoint = validateDriverArgs(args.sublist(0, 3));
    validatePython(args[3]);
    stage = 'marker';
    await verifyNativeMarker(probe, endpoint, args[2]);
    Future<String> digest(Uint8List bytes) => pythonDigest(args[3], bytes);
    AssetSelectionScopeV2 scope({
      String q = '',
      String status = '',
      String category = '',
      String mode = 'all',
      String? location,
      Map<String, Object?>? warranty,
      Map<String, Object?> checkFilter = const {'mode': 'all'},
    }) => AssetSelectionScopeV2.fromJson({
      'q': q,
      'status': status,
      'category': category,
      'locationMode': mode,
      'location': location,
      'sort': 'name_asc',
      'warranty': warranty,
      'check': checkFilter,
    });
    final suffix = List.generate(
      12,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final a = AssetApi(endpoint), b = AssetApi(endpoint);
    clients.addAll([a, b]);
    stage = 'anonymous';
    final request = await probe.getUrl(
      endpoint.replace(path: '/api/v1/assets/export/selection-v2'),
    );
    request.followRedirects = false;
    request.headers.set(
      'x-request-timestamp',
      '${DateTime.now().millisecondsSinceEpoch}',
    );
    final response = await request.close().timeout(const Duration(seconds: 10));
    check(response.statusCode == 401);
    await response.drain<void>().timeout(const Duration(seconds: 10));
    checks['anonymousDenied'] = true;
    stage = 'registration';
    for (final entry in [('a', a), ('b', b)]) {
      await entry.$2.register(
        email: '${entry.$1}$suffix@example.invalid',
        username: '${entry.$1}$suffix',
        name: 'Synthetic selection owner',
        password: 'Synthetic-$suffix-42!',
      );
    }
    stage = 'http-contract';
    await verifySelectionHttp(
      probe,
      endpoint,
      'a$suffix',
      'Synthetic-$suffix-42!',
    );
    checks['noStore'] = true;
    checks['invalidQueryRejected'] = true;
    stage = 'empty';
    check(
      (await a.exportSelectionV2(scope: scope(), digest: digest)).count == 0,
    );
    stage = 'create';
    AssetRecord? first;
    for (var i = 0; i < 51; i++) {
      final row = await a.create(
        AssetInput(
          name: 'Synthetic selection $i',
          category: 'fixture',
          serial: 'SERIAL-%_$i',
          status: 'stored',
          notes: 'Unicode \u4e2d',
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
    stage = 'date-location';
    await a.updateDates(
      await a.readDates(first!.id),
      const AssetDatesInput(
        purchasedOn: '2024-02-29',
        warrantyExpiresOn: '2027-02-28',
      ),
    );
    await a.updateLocation(await a.readLocation(first.id), 'Room %_1');
    await a.updateCheckDate(await a.readCheckDate(first.id), '2024-02-29');
    final checkBefore = await a.readCheckDate(first.id);
    final before = await a.exportInventoryV3(digest: digest);
    stage = 'selection';
    final all = await a.exportSelectionV2(scope: scope(), digest: digest);
    check(
      all.count == 51 &&
          all.records.map((r) => r.record.asset.id).toSet().length == 51,
    );
    checks['all51Matches'] = true;
    final ownB = await b.exportSelectionV2(scope: scope(), digest: digest);
    check(
      ownB.count == 1 &&
          ownB.records.single.record.asset.id == other.id &&
          !all.records.any((r) => r.record.asset.id == other.id),
    );
    checks['ownerIsolation'] = true;
    final literal = await a.exportSelectionV2(
      scope: scope(q: '%_0'),
      digest: digest,
    );
    check(
      literal.count == 1 && literal.records.single.record.asset.id == first.id,
    );
    checks['literalSearch'] = true;
    final combinedScope = scope(
      q: 'SYNTHETIC',
      status: 'stored',
      category: 'fixture',
      mode: 'exact',
      location: 'Room %_1',
      warranty: {
        'filter': 'expiring_soon',
        'asOf': '2027-02-28',
        'through': '2027-03-30',
      },
    );
    final selected = await a.exportSelectionV2(
      scope: combinedScope,
      digest: digest,
    );
    check(
      selected.count == 1 &&
          selected.records.single.record.asset.id == first.id,
    );
    checks['combinedFilters'] = true;
    check(selected.records.single.lastCheckedDate == '2024-02-29');
    for (final entry in [
      (const {'mode': 'unknown'}, 50),
      (const {'mode': 'before', 'cutoff': '2024-02-29'}, 0),
      (const {'mode': 'before', 'cutoff': '2024-03-01'}, 1),
      (const {'mode': 'on_or_after', 'cutoff': '2024-02-29'}, 1),
      (const {'mode': 'on_or_after', 'cutoff': '2024-03-01'}, 0),
    ]) {
      final result = await a.exportSelectionV2(
        scope: scope(checkFilter: entry.$1),
        digest: digest,
      );
      check(result.count == entry.$2);
    }
    checks['checkBoundaries'] = true;
    final legacy = await a.exportSelection(scope: scope().base, digest: digest);
    final legacyEnvelope = jsonDecode(legacy.json) as Map;
    check(legacy.count == 51 && legacyEnvelope['schemaVersion'] == 1);
    check(
      ((jsonDecode(legacyEnvelope['payload'] as String) as Map)['records']
                  as List)
              .any(
                (dynamic record) =>
                    (record as Map).containsKey('lastCheckedDate'),
              ) ==
          false,
    );
    checks['v1Unchanged'] = true;
    final item = selected.records.single;
    check(
      jsonEncode(selected.scope.toQuery()) ==
              jsonEncode(combinedScope.toQuery()) &&
          item.record.location == 'Room %_1' &&
          item.record.dates.purchasedOn == '2024-02-29' &&
          item.record.dates.warrantyExpiresOn == '2027-02-28',
    );
    checks['scopeAndDatesPreserved'] = true;
    final envelope = jsonDecode(selected.json) as Map<String, dynamic>;
    check(
      await digest(
            Uint8List.fromList(utf8.encode(envelope['payload'] as String)),
          ) ==
          envelope['sha256'],
    );
    checks['checksumVerified'] = true;
    final empty = await a.exportSelectionV2(
      scope: scope(q: 'absent synthetic label'),
      digest: digest,
    );
    check(empty.count == 0);
    checks['emptySelection'] = true;
    stage = 'read-only';
    final after = await a.exportInventoryV3(digest: digest);
    String rows(String json) => jsonEncode(
      (jsonDecode((jsonDecode(json) as Map)['payload'] as String)
          as Map)['records'],
    );
    check(after.count == 51 && before.count == 51);
    checks['fullExportUnchanged'] = true;
    check(rows(before.json) == rows(after.json));
    final checkAfter = await a.readCheckDate(first.id);
    check(
      checkAfter.lastCheckedOn == checkBefore.lastCheckedOn &&
          checkAfter.version == checkBefore.version,
    );
    checks['noWrites'] = true;
    stage = 'sign-out';
    a.signOut();
    var refused = false;
    try {
      await a.exportSelectionV2(
        scope: scope(),
        digest: (_) async => throw StateError('must not run'),
      );
    } on AssetFailure catch (error) {
      refused = error.statusCode == 401;
    }
    check(refused);
    checks['signedOutDenied'] = true;
    stdout.writeln(
      jsonEncode({
        'status': 'completed',
        'syntheticOnly': true,
        'selectionExportV2Acceptance': true,
        'owners': 2,
        'assetCount': 51,
        'digest': 'python-sha256-stdin',
        'nativeDialog': 'not-exercised',
        'checks': checks,
      }),
    );
  } catch (_) {
    stderr.writeln(
      'Synthetic selection HTTPS failed at $stage; no automatic retry.',
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

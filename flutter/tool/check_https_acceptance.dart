import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../lib/api/asset.dart';
import '../lib/api/asset_api.dart';
import '../lib/api/asset_dates.dart';
import '../lib/api/asset_details.dart';
import '../lib/api/asset_store.dart';
import 'client_https_acceptance.dart'
    show check, validateDriverArgs, validateMarker;

/// Validate the exact synthetic target before opening any network connection.
Uri validateCheckDriverArgs(List<String> args) => validateDriverArgs(args);

/// Marker-bound check-date acceptance using normal TLS and the real Dart client.
Future<void> main(List<String> args) async {
  final clients = <AssetApi>[];
  final probe = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  var stage = 'arguments';
  try {
    final endpoint = validateCheckDriverArgs(args);
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
    stage = 'anonymous-csrf';
    final path =
        '/api/v1/assets/00000000-0000-4000-8000-000000000000/check-date';
    final anonymous = await probe.getUrl(endpoint.replace(path: path));
    anonymous.followRedirects = false;
    final anonymousResponse = await anonymous.close().timeout(
      const Duration(seconds: 10),
    );
    check(anonymousResponse.statusCode == 401);
    await anonymousResponse.drain<void>();
    final unprotected = await probe.putUrl(endpoint.replace(path: path));
    unprotected.followRedirects = false;
    unprotected.headers.contentType = ContentType.json;
    unprotected.write(jsonEncode({'version': 1, 'lastCheckedOn': null}));
    final unprotectedResponse = await unprotected.close().timeout(
      const Duration(seconds: 10),
    );
    check(unprotectedResponse.statusCode == 403);
    await unprotectedResponse.drain<void>();
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
        name: 'Synthetic check owner',
        password: 'Synthetic-$suffix-42!',
      );
    }
    Future<void> refused(Future<Object?> Function() action, int status) async {
      try {
        await action();
      } on AssetFailure catch (error) {
        check(error.statusCode == status);
        return;
      }
      throw StateError('Expected refusal');
    }

    stage = 'create';
    final row = await a.create(
      const AssetInput(
        name: 'Synthetic check asset',
        category: 'fixture',
        serial: '%_1',
        status: 'stored',
      ),
    );
    await a.updateDates(
      await a.readDates(row.id),
      const AssetDatesInput(
        purchasedOn: '2024-02-29',
        warrantyExpiresOn: '2027-02-28',
      ),
    );
    await a.updateLocation(await a.readLocation(row.id), 'Room %_1');
    final original = await a.readCheckDate(row.id);
    check(original.version == 3 && original.lastCheckedOn == null);
    stage = 'update';
    final saved = await a.updateCheckDate(original, '2024-03-01');
    check(saved.version == 4 && saved.lastCheckedOn == '2024-03-01');
    stage = 'owner-version';
    await refused(() => b.readCheckDate(row.id), 404);
    await refused(() => b.updateCheckDate(saved, null), 409);
    await refused(() => a.updateCheckDate(original, null), 409);
    stage = 'details';
    final selected = await a.readAsset(row.id);
    final details = await AssetDetailsSnapshot.load(
      selected,
      checkSource: a,
      datesSource: a,
      locationSource: a,
    );
    check(
      details.checkDate!.lastCheckedOn == '2024-03-01' &&
          details.location!.location == 'Room %_1' &&
          details.dates!.input.purchasedOn == '2024-02-29' &&
          details.dates!.input.warrantyExpiresOn == '2027-02-28',
    );
    stage = 'checked-before';
    for (final cutoff in ['2024-03-01', '2024-03-02']) {
      for (final scope in ['base', 'warranty', 'location', 'combined']) {
        stage =
            'checked-before-$scope-${cutoff == '2024-03-01' ? 'boundary' : 'earlier'}';
        final result = await a.listCheckedBefore(
          checkBefore: cutoff,
          query: '%_1',
          status: 'stored',
          offset: 0,
          category: 'fixture',
          includeLocation: scope == 'location' || scope == 'combined',
          locationMode: scope == 'location' || scope == 'combined'
              ? 'exact'
              : 'all',
          location: scope == 'location' || scope == 'combined'
              ? 'Room %_1'
              : null,
          warranty: scope == 'warranty' || scope == 'combined'
              ? 'expiring_soon'
              : '',
          asOf: scope == 'warranty' || scope == 'combined' ? '2027-02-01' : '',
        );
        check(
          cutoff == '2024-03-01'
              ? result.page.items.isEmpty
              : result.page.items.length == 1 &&
                    result.page.items.single.id == row.id,
        );
      }
    }
    check(
      (await b.listCheckedBefore(
        checkBefore: '2024-03-02',
        query: '',
        status: '',
        offset: 0,
      )).page.items.isEmpty,
    );
    stage = 'filter-clear';
    check(
      (await a.listUnchecked(
        query: '%_1',
        status: 'stored',
        offset: 0,
        category: 'fixture',
        includeLocation: true,
        locationMode: 'exact',
        location: 'Room %_1',
      )).page.items.isEmpty,
    );
    await a.updateCheckDate(saved, null);
    final page = await a.listUnchecked(
      query: '%_1',
      status: 'stored',
      offset: 0,
      category: 'fixture',
      includeLocation: true,
      locationMode: 'exact',
      location: 'Room %_1',
    );
    check(page.page.items.length == 1 && page.page.items.single.id == row.id);
    check(
      (await b.listUnchecked(
        query: '',
        status: '',
        offset: 0,
      )).page.items.isEmpty,
    );
    check(
      (await a.listCheckedBefore(
        checkBefore: '2024-03-02',
        query: '',
        status: '',
        offset: 0,
      )).page.items.isEmpty,
    );
    stage = 'sign-out';
    a.signOut();
    await refused(() => a.readCheckDate(row.id), 401);
    stdout.writeln(
      jsonEncode({
        'status': 'completed',
        'syntheticOnly': true,
        'checkDateAcceptance': true,
        'checkedBeforeAcceptance': true,
        'owners': 2,
        'nativeDialog': 'not-exercised',
      }),
    );
  } catch (error) {
    stdout.writeln(
      jsonEncode({
        'status': 'failed',
        'stage': stage,
        'failureKind': error is AssetFailure
            ? 'api'
            : error is FormatException
            ? 'format'
            : 'assertion',
        if (error is AssetFailure && error.statusCode != null)
          'httpStatus': error.statusCode,
      }),
    );
  } finally {
    for (final client in clients) {
      client.close();
    }
    probe.close(force: true);
  }
}

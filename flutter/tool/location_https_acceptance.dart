import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../lib/api/asset.dart';
import '../lib/api/asset_details.dart';
import '../lib/api/asset_dates.dart';
import '../lib/api/asset_location.dart';
import 'export_https_acceptance.dart' show pythonDigest, validatePython;
import '../lib/api/asset_store.dart';
import '../lib/api/asset_api.dart';
import 'client_https_acceptance.dart'
    show check, validateDriverArgs, validateMarker;

/// Validate all opt-in arguments before constructing a client or opening a socket.
Uri validateLocationDriverArgs(List<String> args) {
  check(args.length == 4);
  final endpoint = validateDriverArgs(args.take(3).toList());
  validatePython(args[3]);
  return endpoint;
}

/// Marker-bound synthetic location acceptance; never disables TLS verification.
Future<void> main(List<String> args) async {
  final clients = <AssetApi>[];
  final probe = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  var stage = 'arguments';
  try {
    final endpoint = validateLocationDriverArgs(args);
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
        name: 'Synthetic location owner',
        password: 'Synthetic-$suffix-42!',
      );
    }
    const input = AssetInput(
      name: 'Synthetic dated router',
      category: 'network',
      status: 'stored',
    );
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

    stage = 'anonymous';
    final anonymous = await probe.getUrl(
      endpoint.replace(path: '/api/v1/assets/locations/overview'),
    );
    anonymous.followRedirects = false;
    final anonymousResponse = await anonymous.close().timeout(
      const Duration(seconds: 10),
    );
    check(anonymousResponse.statusCode == 401);
    await anonymousResponse.drain<void>();
    final unprotected = await probe.putUrl(
      endpoint.replace(
        path: '/api/v1/assets/00000000-0000-4000-8000-000000000000/location',
      ),
    );
    unprotected.headers.contentType = ContentType.json;
    unprotected.write(jsonEncode({'version': 1, 'location': null}));
    final unprotectedResponse = await unprotected.close().timeout(
      const Duration(seconds: 10),
    );
    check(unprotectedResponse.statusCode == 403);
    await unprotectedResponse.drain<void>();
    stage = 'overview-empty';
    final empty = await a.locationOverview();
    check(empty.total == 0 && empty.unknown == 0 && empty.locations.isEmpty);
    stage = 'create';
    final row = await a.create(input);
    final other = await b.create(input);
    final original = await a.readLocation(row.id);
    check(original.location == null && original.version == row.version);
    stage = 'location-update';
    final changed = await a.updateLocation(original, ' Room %_ ');
    check(changed.location == 'Room %_' && changed.version == 2);
    stage = 'owner-isolation';
    await refused(() => b.readLocation(row.id), 404);
    await refused(() => b.updateLocation(changed, 'Other'), 409);
    check((await b.readLocation(other.id)).version == 1);
    stage = 'stale-version';
    await refused(() => a.updateLocation(original, 'Stale'), 409);
    await a.updateDates(
      await a.readDates(row.id),
      const AssetDatesInput(
        purchasedOn: '2024-02-29',
        warrantyExpiresOn: '2027-02-28',
      ),
    );
    await refused(() => a.updateLocation(changed, 'Stale after dates'), 409);
    stage = 'legacy-preservation';
    final listed = (await a.list(
      query: '',
      status: '',
      offset: 0,
    )).items.single;
    await a.update(
      listed,
      const AssetInput(
        name: 'Edited legacy asset',
        category: 'network',
        status: 'repair',
      ),
    );
    check((await a.readLocation(row.id)).location == 'Room %_');
    final savedDates = await a.readDates(row.id);
    check(
      savedDates.input.purchasedOn == '2024-02-29' &&
          savedDates.input.warrantyExpiresOn == '2027-02-28',
    );
    stage = 'details';
    final selected = (await a.list(
      query: '',
      status: '',
      offset: 0,
    )).items.single;
    final details = await AssetDetailsSnapshot.load(
      selected,
      datesSource: a,
      locationSource: a,
    );
    check(
      details.dates!.input.purchasedOn == '2024-02-29' &&
          details.dates!.input.warrantyExpiresOn == '2027-02-28' &&
          details.location!.location == 'Room %_',
    );
    final unchanged = (await a.list(
      query: '',
      status: '',
      offset: 0,
    )).items.single;
    check(
      unchanged.version == selected.version &&
          unchanged.input.name == selected.input.name,
    );
    await refused(
      () => AssetDetailsSnapshot.load(
        selected,
        datesSource: b,
        locationSource: b,
      ),
      404,
    );
    var staleRejected = false;
    try {
      await AssetDetailsSnapshot.load(row, datesSource: a, locationSource: a);
    } on AssetFailure {
      staleRejected = true;
    }
    check(staleRejected);
    final unknown = await AssetDetailsSnapshot.load(
      other,
      datesSource: b,
      locationSource: b,
    );
    check(
      unknown.dates!.input.purchasedOn == null &&
          unknown.dates!.input.warrantyExpiresOn == null &&
          unknown.location!.location == null,
    );
    stage = 'pagination';
    for (var i = 0; i < 51; i++) {
      final asset = await a.create(
        AssetInput(
          name: 'Paging literal %_ $i',
          category: 'network',
          status: 'stored',
        ),
      );
      await a.updateLocation(
        AssetLocation(id: asset.id, version: asset.version, location: null),
        'Room %_',
      );
      await a.updateDates(
        await a.readDates(asset.id),
        const AssetDatesInput(
          purchasedOn: null,
          warrantyExpiresOn: '2027-02-28',
        ),
      );
    }
    final first = await a.listLocations(
      query: '%_',
      status: 'stored',
      category: 'network',
      offset: 0,
      locationMode: 'exact',
      location: 'Room %_',
      warranty: 'expiring_soon',
      asOf: '2027-02-01',
    );
    check(first.items.length == 50 && first.nextOffset == 50);
    final last = await a.listLocations(
      query: '%_',
      status: 'stored',
      category: 'network',
      offset: 50,
      locationMode: 'exact',
      location: 'Room %_',
      warranty: 'expiring_soon',
      asOf: first.warrantyPage!.asOf,
    );
    check(last.items.length == 1 && last.nextOffset == null);
    check(
      {
            ...first.items.map((e) => e.asset.id),
            ...last.items.map((e) => e.asset.id),
          }.length ==
          51,
    );
    check(
      (await a.listLocations(
        query: '',
        status: '',
        offset: 0,
        locationMode: 'unknown',
      )).items.isEmpty,
    );
    check(
      (await a.listLocations(
        query: '',
        status: '',
        offset: 0,
        locationMode: 'exact',
        location: 'room %_',
      )).items.isEmpty,
    );
    check(
      (await b.listLocations(
        query: '',
        status: '',
        offset: 0,
        locationMode: 'exact',
        location: 'Room %_',
      )).items.isEmpty,
    );
    stage = 'overview-full';
    final overview = await a.locationOverview();
    check(overview.total == 52 && overview.unknown == 0);
    check(
      overview.locations.single.location == 'Room %_' &&
          overview.locations.single.count == 52,
    );
    final foreign = await b.locationOverview();
    check(
      foreign.total == 1 && foreign.unknown == 1 && foreign.locations.isEmpty,
    );
    stage = 'export';
    final v1 = await a.exportInventory(
      digest: (bytes) => pythonDigest(args[3], bytes),
    );
    final v2 = await a.exportInventoryV2(
      digest: (bytes) => pythonDigest(args[3], bytes),
    );
    check(v1.records.length == 52 && v2.records.length == 52);
    stage = 'clear';
    final cleared = await a.updateLocation(await a.readLocation(row.id), null);
    check(cleared.location == null);
    check(
      (await a.listLocations(
            query: '',
            status: '',
            offset: 0,
            locationMode: 'unknown',
          )).items.single.asset.id ==
          row.id,
    );
    check((await a.readDates(row.id)).input.purchasedOn == '2024-02-29');
    stage = 'overview-clear';
    final afterClear = await a.locationOverview();
    check(
      afterClear.total == 52 &&
          afterClear.unknown == 1 &&
          afterClear.locations.single.count == 51,
    );
    stage = 'sign-out';
    a.signOut();
    await refused(() => a.locationOverview(), 401);
    await refused(() => a.readLocation(row.id), 401);
    stdout.writeln(
      jsonEncode({
        'status': 'completed',
        'syntheticOnly': true,
        'locationAcceptance': true,
        'locationOverviewAcceptance': true,
        'assetDetailsAcceptance': true,
        'owners': 2,
        'assetCount': 53,
        'digest': 'python-sha256-stdin',
        'nativeDialog': 'not-exercised',
      }),
    );
  } catch (_) {
    stderr.writeln(
      'Location HTTPS acceptance failed at $stage; no automatic retry.',
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

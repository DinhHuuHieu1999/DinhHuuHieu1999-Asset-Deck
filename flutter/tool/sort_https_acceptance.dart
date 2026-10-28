import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../lib/api/asset.dart';
import '../lib/api/asset_api.dart';
import '../lib/api/asset_dates.dart';
import 'client_https_acceptance.dart' show check, validateDriverArgs;
import 'native_https_seed.dart' show verifyNativeMarker;

/// Mirror PostgreSQL C ordering for UTF-8 names with a unique ASCII UUID tie-breaker.
int compareSortFixtureRecords(AssetRecord a, AssetRecord b) {
  final x = utf8.encode(a.input.name), y = utf8.encode(b.input.name);
  for (var i = 0; i < min(x.length, y.length); i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  return x.length.compareTo(y.length) != 0
      ? x.length.compareTo(y.length)
      : a.id.compareTo(b.id);
}

/// Marker-bound synthetic sort checks; default TLS validation remains enabled.
Future<void> main(List<String> args) async {
  final probe = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final clients = <AssetApi>[];
  var stage = 'arguments';
  try {
    final endpoint = validateDriverArgs(args);
    stage = 'marker';
    await verifyNativeMarker(probe, endpoint, args[2]);
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
        name: 'Synthetic sort owner',
        password: 'Synthetic-$suffix-42!',
      );
    }
    stage = 'create';
    final rows = <AssetRecord>[];
    for (var i = 0; i < 53; i++) {
      final row = await a.create(
        AssetInput(
          name: [
            'Alpha %_',
            'alpha %_',
            '\u00c9clair %_',
            '\u91cd\u590d %_',
          ][i % 4],
          category: 'fixture',
          serial: 'SORT-%_1',
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
      await a.updateLocation(await a.readLocation(row.id), '%_Room');
      rows.add(row);
    }
    final other = await b.create(
      const AssetInput(name: 'AAA %_', category: 'fixture', status: 'stored'),
    );
    await a.create(
      const AssetInput(
        name: 'Excluded %_',
        category: 'fixture',
        status: 'retired',
      ),
    );
    final expected = [...rows]..sort(compareSortFixtureRecords);
    final expectedIds = expected.map((r) => r.id).toList();
    stage = 'pagination';
    for (final kind in ['regular', 'warranty', 'location']) {
      Future<(List<AssetRecord>, int?)> list(int offset, String sort) async {
        if (kind == 'regular') {
          final page = await a.list(
            query: '%_',
            status: 'stored',
            category: 'fixture',
            offset: offset,
            sort: sort,
          );
          return (page.items, page.nextOffset);
        }
        if (kind == 'warranty') {
          final page = await a.listWarranty(
            query: '%_',
            status: 'stored',
            category: 'fixture',
            offset: offset,
            sort: sort,
            warranty: 'expiring_soon',
            asOf: '2027-02-01',
          );
          return (
            page.items.map((item) => item.asset).toList(),
            page.nextOffset,
          );
        }
        final page = await a.listLocations(
          query: '%_',
          status: 'stored',
          category: 'fixture',
          offset: offset,
          sort: sort,
          locationMode: 'exact',
          location: '%_Room',
          warranty: 'expiring_soon',
          asOf: '2027-02-01',
        );
        return (page.items.map((item) => item.asset).toList(), page.nextOffset);
      }

      final first = await list(0, 'name_asc'),
          last = await list(50, 'name_asc');
      check(
        first.$1.length == 50 &&
            first.$2 == 50 &&
            last.$1.length == 3 &&
            last.$2 == null,
      );
      final combined = [...first.$1, ...last.$1];
      check(
        jsonEncode(combined.map((r) => r.id).toList()) ==
            jsonEncode(expectedIds),
      );
      check(combined.every((r) => r.version == 3));
      check(!combined.any((r) => r.id == other.id));
      final recent = [
        ...(await list(0, 'updated_desc')).$1,
        ...(await list(50, 'updated_desc')).$1,
      ];
      final sortedRecent = [...recent]
        ..sort(
          (x, y) => y.updatedAt.compareTo(x.updatedAt) != 0
              ? y.updatedAt.compareTo(x.updatedAt)
              : y.id.compareTo(x.id),
        );
      check(
        jsonEncode(recent.map((r) => r.id).toList()) ==
            jsonEncode(sortedRecent.map((r) => r.id).toList()),
      );
    }
    stage = 'owner-isolation';
    check(
      (await b.list(
            query: '',
            status: '',
            offset: 0,
            sort: 'name_asc',
          )).items.single.id ==
          other.id,
    );
    stage = 'default';
    final implicit = await a.list(query: '%_', status: 'stored', offset: 0);
    final explicit = await a.list(
      query: '%_',
      status: 'stored',
      offset: 0,
      sort: 'updated_desc',
    );
    check(
      jsonEncode(implicit.items.map((r) => r.id).toList()) ==
          jsonEncode(explicit.items.map((r) => r.id).toList()),
    );
    stdout.writeln(
      jsonEncode({
        'status': 'completed',
        'syntheticOnly': true,
        'sortAcceptance': true,
        'owners': 2,
        'matchingRecords': 53,
        'listPaths': 3,
      }),
    );
  } catch (_) {
    stdout.writeln(jsonEncode({'status': 'failed', 'stage': stage}));
    exitCode = 1;
  } finally {
    probe.close(force: true);
    for (final client in clients) {
      client.close();
    }
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../lib/api/asset.dart';
import '../lib/api/asset_api.dart';
import '../lib/api/asset_dates.dart';
import 'client_https_acceptance.dart' show check, validateDriverArgs;
import 'native_https_seed.dart' show verifyNativeMarker;

/// Independent expected date order: known oldest first, Unknown last, stable ID.
int compareCheckSortEntries((String, String?) a, (String, String?) b) {
  final x = a.$2, y = b.$2;
  final dateOrder = x == y
      ? 0
      : x == null
      ? 1
      : y == null
      ? -1
      : x.compareTo(y);
  return dateOrder != 0 ? dateOrder : a.$1.compareTo(b.$1);
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
    final checks = <String, String?>{};
    final versions = <String, int>{};
    for (var i = 0; i < 56; i++) {
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
      final date = i < 51
          ? '2023-12-31'
          : i < 54
          ? '2024-02-29'
          : null;
      if (date != null)
        await a.updateCheckDate(await a.readCheckDate(row.id), date);
      final saved = await a.readCheckDate(row.id);
      checks[row.id] = date;
      versions[row.id] = saved.version;
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
    final expected = checks.entries.map((e) => (e.key, e.value)).toList()
      ..sort(compareCheckSortEntries);
    final expectedIds = expected.map((r) => r.$1).toList();
    stage = 'pagination';
    for (final kind in ['regular', 'warranty', 'location', 'combined']) {
      Future<(List<AssetRecord>, int?)> list(
        int offset,
        String sort, {
        String checkMode = 'all',
      }) async {
        if (kind == 'regular') {
          final page = await a.list(
            query: '%_',
            status: 'stored',
            category: 'fixture',
            offset: offset,
            sort: sort,
            unchecked: checkMode == 'unknown',
            checkBefore: checkMode == 'before' ? '2024-02-29' : '',
            checkOnOrAfter: checkMode == 'after' ? '2024-02-29' : '',
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
            unchecked: checkMode == 'unknown',
            checkBefore: checkMode == 'before' ? '2024-02-29' : '',
            checkOnOrAfter: checkMode == 'after' ? '2024-02-29' : '',
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
          unchecked: checkMode == 'unknown',
          checkBefore: checkMode == 'before' ? '2024-02-29' : '',
          checkOnOrAfter: checkMode == 'after' ? '2024-02-29' : '',
          locationMode: 'exact',
          location: '%_Room',
          warranty: kind == 'combined' ? 'expiring_soon' : '',
          asOf: kind == 'combined' ? '2027-02-01' : '',
        );
        return (page.items.map((item) => item.asset).toList(), page.nextOffset);
      }

      final first = await list(0, 'checked_asc'),
          last = await list(50, 'checked_asc');
      check(
        first.$1.length == 50 &&
            first.$2 == 50 &&
            last.$1.length == 6 &&
            last.$2 == null,
      );
      final combined = [...first.$1, ...last.$1];
      check(
        jsonEncode(combined.map((r) => r.id).toList()) ==
            jsonEncode(expectedIds),
      );
      check(combined.every((r) => r.version == versions[r.id]));
      check(!combined.any((r) => r.id == other.id));
      for (final mode in ['unknown', 'before', 'after']) {
        final matching = expected
            .where(
              (entry) => mode == 'unknown'
                  ? entry.$2 == null
                  : entry.$2 != null &&
                        (mode == 'before'
                            ? entry.$2!.compareTo('2024-02-29') < 0
                            : entry.$2!.compareTo('2024-02-29') >= 0),
            )
            .map((e) => e.$1)
            .toList();
        final firstFiltered = await list(0, 'checked_asc', checkMode: mode);
        final filtered = [...firstFiltered.$1];
        if (matching.length > 50) {
          check(firstFiltered.$2 == 50);
          final tail = await list(50, 'checked_asc', checkMode: mode);
          check(tail.$2 == null);
          filtered.addAll(tail.$1);
        } else {
          check(firstFiltered.$2 == null);
        }
        check(
          jsonEncode(filtered.map((r) => r.id).toList()) ==
              jsonEncode(matching),
        );
      }
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
    stage = 'unchanged-checks';
    for (final row in rows) {
      final saved = await a.readCheckDate(row.id);
      check(
        saved.lastCheckedOn == checks[row.id] &&
            saved.version == versions[row.id],
      );
    }
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
        'checkSortAcceptance': true,
        'owners': 2,
        'matchingRecords': 56,
        'listPaths': 4,
        'checkFilterCases': 12,
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

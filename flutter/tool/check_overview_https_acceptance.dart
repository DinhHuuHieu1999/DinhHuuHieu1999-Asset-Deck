import '../lib/api/asset.dart';
import '../lib/api/asset_api.dart';
import '../lib/api/asset_dates.dart';
import 'check_https_acceptance.dart' show runCheckAcceptance;
import 'client_https_acceptance.dart' show check;

/// Run the fixed overview scenarios through normal TLS and the real API client.
Future<void> main(List<String> args) =>
    runCheckAcceptance(args, overviewProbe: checkOverviewAcceptance);

/// Verify complete owner counts, equality boundaries and exact scoped lists.
Future<void> checkOverviewAcceptance(AssetApi a, AssetApi b) async {
  const cutoff = '2024-03-01';
  final initial = await a.checkOverview(cutoff: cutoff);
  check(
    initial.total == 1 &&
        initial.unknown == 1 &&
        initial.before == 0 &&
        initial.onOrAfter == 0,
  );
  check((await b.checkOverview(cutoff: cutoff)).total == 0);
  final ids = <String>[];
  for (final date in ['2024-02-29', cutoff, '2024-03-02']) {
    final row = await a.create(
      const AssetInput(
        name: 'Synthetic overview asset',
        category: 'overview',
        serial: 'OVERVIEW-%_1',
        status: 'stored',
      ),
    );
    await a.updateDates(
      await a.readDates(row.id),
      const AssetDatesInput(
        purchasedOn: '2024-01-01',
        warrantyExpiresOn: '2025-01-01',
      ),
    );
    await a.updateLocation(await a.readLocation(row.id), 'Overview room %_1');
    await a.updateCheckDate(await a.readCheckDate(row.id), date);
    ids.add(row.id);
  }
  final overview = await a.checkOverview(cutoff: cutoff);
  check(
    overview.total == 4 &&
        overview.unknown == 1 &&
        overview.before == 1 &&
        overview.onOrAfter == 2,
  );
  check((await b.checkOverview(cutoff: cutoff)).total == 0);
  final versions = <String, int>{};
  for (final id in ids) {
    versions[id] = (await a.readAsset(id)).version;
  }
  for (final scope in ['base', 'warranty', 'location', 'combined']) {
    final location = scope == 'location' || scope == 'combined';
    final warranty = scope == 'warranty' || scope == 'combined';
    final page = await a.listCheckedOnOrAfter(
      checkOnOrAfter: cutoff,
      query: 'OVERVIEW-%_1',
      status: 'stored',
      category: 'overview',
      offset: 0,
      includeLocation: location,
      locationMode: location ? 'exact' : 'all',
      location: location ? 'Overview room %_1' : null,
      warranty: warranty ? 'expired' : '',
      asOf: warranty ? '2026-01-01' : '',
    );
    check(page.page.items.length == 2 && page.page.nextOffset == null);
    check(
      page.page.items.map((row) => row.id).toSet().containsAll(ids.skip(1)),
    );
  }
  for (final id in ids) {
    check((await a.readAsset(id)).version == versions[id]);
  }
  final again = await a.checkOverview(cutoff: cutoff);
  check(
    again.total == overview.total &&
        again.unknown == overview.unknown &&
        again.before == overview.before &&
        again.onOrAfter == overview.onOrAfter,
  );
}

import 'package:flutter_test/flutter_test.dart';

import '../lib/api/asset.dart';
import '../tool/sort_https_acceptance.dart' show compareSortFixtureRecords;

void main() {
  AssetRecord row(String name, String id) => AssetRecord(
    id: id,
    input: AssetInput(name: name, category: 'fixture', status: 'stored'),
    version: 1,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
  test('expected name order follows UTF-8 C bytes and ID tie-breaker', () {
    final rows = [
      row('\u91cd\u590d', '1'),
      row('alpha', '2'),
      row('Alpha', '3'),
      row('\u00c9clair', '4'),
      row('Alpha', '1'),
    ]..sort(compareSortFixtureRecords);
    expect(rows.map((r) => r.id), ['1', '3', '2', '4', '1']);
  });
  test('prefix names sort before longer names', () {
    expect(
      compareSortFixtureRecords(row('A', '2'), row('AA', '1')),
      lessThan(0),
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset_location_overview.dart';

void main() {
  Map<String, Object?> snapshot() => {
    'complete': true,
    'total': 3,
    'unknown': 1,
    'locations': [
      {'location': 'Room %_1', 'count': 2},
    ],
  };
  test('complete counts preserve exact labels and immutable groups', () {
    final result = AssetLocationOverview.fromJson(snapshot());
    expect(result.total, 3);
    expect(result.unknown, 1);
    expect(result.locations.single.location, 'Room %_1');
    expect(() => result.locations.clear(), throwsUnsupportedError);
  });
  test('zero inventory is explicit and complete', () {
    expect(
      AssetLocationOverview.fromJson({
        'complete': true,
        'total': 0,
        'unknown': 0,
        'locations': [],
      }).total,
      0,
    );
  });
  test('rejects missing/extra/incomplete fields and inconsistent totals', () {
    for (final value in [
      snapshot()..remove('unknown'),
      snapshot()..['owner'] = 'other',
      snapshot()..['complete'] = false,
      snapshot()..['total'] = 4,
    ]) {
      expect(
        () => AssetLocationOverview.fromJson(value),
        throwsFormatException,
      );
    }
  });
  test('rejects unsafe and malformed counts', () {
    for (final count in [-1, 1.5, '3', 9007199254740992, null]) {
      expect(
        () => AssetLocationOverview.fromJson(snapshot()..['total'] = count),
        throwsFormatException,
      );
    }
  });
  test('rejects null/blank/unnormalized/duplicate group labels', () {
    for (final label in [null, '', ' A ', 'A\u0000']) {
      expect(
        () => AssetLocationOverview.fromJson(
          snapshot()
            ..['locations'] = [
              {'location': label, 'count': 2},
            ],
        ),
        throwsFormatException,
      );
    }
    expect(
      () => AssetLocationOverview.fromJson(
        snapshot()
          ..['locations'] = [
            {'location': 'A', 'count': 1},
            {'location': 'A', 'count': 1},
          ],
      ),
      throwsFormatException,
    );
  });
  test('refuses oversized groups and zero-count known labels', () {
    expect(
      () => AssetLocationOverview.fromJson(
        snapshot()
          ..['locations'] = List.generate(
            1001,
            (i) => {'location': '$i', 'count': 1},
          ),
      ),
      throwsFormatException,
    );
    expect(
      () => AssetLocationOverview.fromJson(
        snapshot()
          ..['locations'] = [
            {'location': 'A', 'count': 0},
          ],
      ),
      throwsFormatException,
    );
  });
}

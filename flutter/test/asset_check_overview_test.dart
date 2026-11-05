import 'package:asset_desk/api/asset_check.dart';
import 'package:asset_desk/api/asset_check_overview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inclusive cutoff query refuses conflicts and malformed dates', () {
    expect(assetCheckQuery(onOrAfter: '2024-02-29'), {
      'checkMode': 'on_or_after',
      'checkOnOrAfter': '2024-02-29',
    });
    expect(
      () => assetCheckQuery(unchecked: true, onOrAfter: '2024-02-29'),
      throwsFormatException,
    );
    expect(
      () => assetCheckQuery(before: '2024-02-29', onOrAfter: '2024-02-29'),
      throwsFormatException,
    );
    for (final day in ['2023-02-29', ' 2024-02-29', '2024-02-29T00:00:00Z']) {
      expect(() => assetCheckQuery(onOrAfter: day), throwsFormatException);
    }
  });

  const cutoff = '2024-02-29';
  Map<String, Object?> fixture() => {
    'complete': true,
    'cutoff': cutoff,
    'total': 6,
    'unknown': 1,
    'before': 2,
    'onOrAfter': 3,
  };
  test('parses a complete partition at the requested cutoff', () {
    final result = AssetCheckOverview.fromJson(fixture(), cutoff: cutoff);
    expect(
      [result.total, result.unknown, result.before, result.onOrAfter],
      [6, 1, 2, 3],
    );
    expect(result.cutoff, cutoff);
  });
  test('rejects malformed, partial and inconsistent responses', () {
    for (final change in <Map<String, Object?>>[
      {'complete': false},
      {'cutoff': '2024-03-01'},
      {'total': 7},
      {'unknown': -1},
      {'before': '2'},
      {'onOrAfter': 3.0},
      {'total': 9007199254740992},
      {'extra': true},
    ]) {
      expect(
        () => AssetCheckOverview.fromJson({
          ...fixture(),
          ...change,
        }, cutoff: cutoff),
        throwsFormatException,
      );
    }
    for (final field in fixture().keys) {
      final value = fixture()..remove(field);
      expect(
        () => AssetCheckOverview.fromJson(value, cutoff: cutoff),
        throwsFormatException,
      );
    }
  });
  test('rejects invalid requested cutoff even with matching echo', () {
    for (final day in ['', '2023-02-29', ' 2024-02-29', '0000-01-01']) {
      expect(
        () => AssetCheckOverview.fromJson({
          ...fixture(),
          'cutoff': day,
        }, cutoff: day),
        throwsFormatException,
      );
    }
  });
  test('accepts empty counts and rejects sum overflow', () {
    expect(
      AssetCheckOverview.fromJson({
        ...fixture(),
        'total': 0,
        'unknown': 0,
        'before': 0,
        'onOrAfter': 0,
      }, cutoff: cutoff).total,
      0,
    );
    expect(
      () => AssetCheckOverview.fromJson({
        ...fixture(),
        'total': 9007199254740991,
        'unknown': 9007199254740991,
        'before': 1,
        'onOrAfter': 0,
      }, cutoff: cutoff),
      throwsFormatException,
    );
  });
}

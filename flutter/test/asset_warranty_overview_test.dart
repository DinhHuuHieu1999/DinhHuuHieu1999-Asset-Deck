import 'package:asset_desk/api/asset_warranty_overview.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> warrantyOverviewFixture() => {
  'complete': true,
  'asOf': '2026-10-27',
  'through': '2026-11-26',
  'total': 57,
  'expired': 51,
  'expiringSoon': 2,
  'later': 3,
  'unknown': 1,
};

void main() {
  test('accepts complete counts and exact explicit reference', () {
    final result = AssetWarrantyOverview.fromJson(
      warrantyOverviewFixture(),
      asOf: '2026-10-27',
    );
    expect(
      [
        result.total,
        result.expired,
        result.expiringSoon,
        result.later,
        result.unknown,
      ],
      [57, 51, 2, 3, 1],
    );
    expect(result.through, '2026-11-26');
  });
  test('accepts empty and max-safe totals without truncation', () {
    final zero = {
      ...warrantyOverviewFixture(),
      'total': 0,
      'expired': 0,
      'expiringSoon': 0,
      'later': 0,
      'unknown': 0,
    };
    expect(AssetWarrantyOverview.fromJson(zero).total, 0);
    expect(
      AssetWarrantyOverview.fromJson({
        ...zero,
        'total': 9007199254740991,
        'unknown': 9007199254740991,
      }).unknown,
      9007199254740991,
    );
  });
  for (final field in warrantyOverviewFixture().keys) {
    test('missing $field fails closed', () {
      final value = warrantyOverviewFixture()..remove(field);
      expect(
        () => AssetWarrantyOverview.fromJson(value),
        throwsFormatException,
      );
    });
  }
  for (final field in [
    'total',
    'expired',
    'expiringSoon',
    'later',
    'unknown',
  ]) {
    for (final invalid in [-1, 1.5, '1', true, null, 9007199254740992]) {
      test('invalid $field $invalid fails closed', () {
        expect(
          () => AssetWarrantyOverview.fromJson({
            ...warrantyOverviewFixture(),
            field: invalid,
          }),
          throwsFormatException,
        );
      });
    }
  }
  for (final change in <Map<String, Object?>>[
    {'total': 58},
    {'total': 9007199254740991, 'expired': 9007199254740991},
    {'complete': false},
    {'complete': 1},
    {'ownerId': 'not-allowed'},
    {'asOf': '2026-02-29'},
    {'asOf': '2026-10-27\n'},
    {'through': '2026-11-25'},
    {'through': null},
    {'asOf': null},
  ]) {
    test('rejects malformed or inconsistent envelope $change', () {
      expect(
        () => AssetWarrantyOverview.fromJson({
          ...warrantyOverviewFixture(),
          ...change,
        }),
        throwsFormatException,
      );
    });
  }
  test('refuses reference echo mismatch', () {
    expect(
      () => AssetWarrantyOverview.fromJson(
        warrantyOverviewFixture(),
        asOf: '2026-10-26',
      ),
      throwsFormatException,
    );
  });
  test('validates Gregorian century and capped horizon', () {
    for (final pair in [
      ('0001-01-01', '0001-01-31'),
      ('2000-02-29', '2000-03-30'),
      ('9999-12-31', '9999-12-31'),
    ]) {
      expect(
        AssetWarrantyOverview.fromJson({
          ...warrantyOverviewFixture(),
          'asOf': pair.$1,
          'through': pair.$2,
        }).asOf,
        pair.$1,
      );
    }
  });
}

import 'package:asset_desk/api/asset_dates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final date in ['0001-01-01', '9999-12-31', '2000-02-29', '2024-02-29']) {
    test(
      'accepts calendar boundary $date',
      () => expect(isAssetCalendarDate(date), isTrue),
    );
  }
  for (final date in <Object?>[
    '0000-01-01',
    '1900-02-29',
    '2026-02-29',
    '2026-04-31',
    '2026-00-01',
    '2026-13-01',
    '2026-01-00',
    '2026-1-01',
    '2026-01-01\n',
    ' 2026-01-01',
    '2026-01-01T00:00:00Z',
    null,
    20260101,
  ]) {
    test(
      'rejects invalid calendar value $date',
      () => expect(isAssetCalendarDate(date), isFalse),
    );
  }
  test('explicit nulls and equal or independent dates are accepted', () {
    for (final input in [
      const AssetDatesInput(purchasedOn: null, warrantyExpiresOn: null),
      const AssetDatesInput(purchasedOn: null, warrantyExpiresOn: '2030-01-01'),
      const AssetDatesInput(purchasedOn: '2030-01-01', warrantyExpiresOn: null),
      const AssetDatesInput(
        purchasedOn: '2030-01-01',
        warrantyExpiresOn: '2030-01-01',
      ),
    ]) {
      expect(input.toJson(version: 1).keys, [
        'version',
        'purchasedOn',
        'warrantyExpiresOn',
      ]);
    }
  });
  test('rejects reversed dates and unsafe mutation versions', () {
    const reversed = AssetDatesInput(
      purchasedOn: '2030-01-02',
      warrantyExpiresOn: '2030-01-01',
    );
    expect(() => reversed.toJson(version: 1), throwsFormatException);
    const empty = AssetDatesInput(purchasedOn: null, warrantyExpiresOn: null);
    for (final version in [0, -1, 2147483647]) {
      expect(() => empty.toJson(version: version), throwsFormatException);
    }
  });
  test('strict response distinguishes absent fields from explicit null', () {
    final row = <String, Object?>{
      'id': '11111111-1111-4111-8111-111111111111',
      'version': 2147483647,
      'purchasedOn': null,
      'warrantyExpiresOn': null,
    };
    expect(AssetDates.fromJson(row).version, 2147483647);
    for (final invalid in [
      {...row}..remove('purchasedOn'),
      {...row, 'owner': 'unexpected'},
      {...row, 'version': 1.0},
      {...row, 'id': '../other'},
      {...row, 'purchasedOn': 123},
      {...row, 'purchasedOn': '1900-02-29'},
    ]) {
      expect(() => AssetDates.fromJson(invalid), throwsFormatException);
    }
  });
}

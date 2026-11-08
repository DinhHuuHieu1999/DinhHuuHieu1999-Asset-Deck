import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset_warranty.dart';

import 'asset_test.dart' show record;

Map<String, Object?> warrantyFixture({
  String filter = 'expiring_soon',
  String day = '2026-10-26',
  List<Object?>? items,
  Object? next,
}) => {
  'items':
      items ??
      [
        {...record(), 'purchasedOn': null, 'warrantyExpiresOn': day},
      ],
  'nextOffset': next,
  'warranty': filter,
  'asOf': day,
  'through': assetWarrantyThrough(day),
};

void main() {
  AssetWarrantyPage parse(
    Map<String, Object?> value, {
    String filter = 'expiring_soon',
    String day = '',
    int offset = 0,
  }) => AssetWarrantyPage.fromJson(
    value,
    warranty: filter,
    asOf: day,
    offset: offset,
  );
  for (final pair in [
    ['0001-01-01', '0001-01-31'],
    ['0099-12-20', '0100-01-19'],
    ['1900-02-01', '1900-03-03'],
    ['2000-02-01', '2000-03-02'],
    ['2024-02-01', '2024-03-02'],
    ['9999-12-20', '9999-12-31'],
  ]) {
    test(
      'calendar horizon ${pair[0]}',
      () => expect(assetWarrantyThrough(pair[0]), pair[1]),
    );
  }
  test('accepts empty, immutable and explicit reference pages', () {
    expect(parse(warrantyFixture(items: [])).items, isEmpty);
    final page = parse(warrantyFixture(), day: '2026-10-26');
    expect(page.asOf, '2026-10-26');
    expect(page.through, '2026-11-25');
    expect(page.items.single.dates.warrantyExpiresOn, '2026-10-26');
    expect(() => page.items.clear(), throwsUnsupportedError);
  });
  test('accepts first and last inclusive upcoming days, excludes expired', () {
    for (final end in ['2026-10-26', '2026-11-25']) {
      expect(
        parse(
          warrantyFixture(
            items: [
              {...record(), 'purchasedOn': null, 'warrantyExpiresOn': end},
            ],
          ),
        ).items,
        hasLength(1),
      );
    }
    expect(
      parse(
        warrantyFixture(
          filter: 'expired',
          items: [
            {
              ...record(),
              'purchasedOn': null,
              'warrantyExpiresOn': '2026-10-25',
            },
          ],
        ),
        filter: 'expired',
      ).items,
      hasLength(1),
    );
  });
  for (final end in [
    null,
    '2026-10-25',
    '2026-11-26',
    '2026-02-29',
    '2026-10-26\n',
  ]) {
    test('rejects nonmatching upcoming warranty $end', () {
      expect(
        () => parse(
          warrantyFixture(
            items: [
              {...record(), 'purchasedOn': null, 'warrantyExpiresOn': end},
            ],
          ),
        ),
        throwsFormatException,
      );
    });
  }
  test('expired excludes today and unknown, validates purchase ordering', () {
    for (final end in [null, '2026-10-26', '2026-11-25']) {
      expect(
        () => parse(
          warrantyFixture(
            filter: 'expired',
            items: [
              {...record(), 'purchasedOn': null, 'warrantyExpiresOn': end},
            ],
          ),
          filter: 'expired',
        ),
        throwsFormatException,
      );
    }
    expect(
      () => parse(
        warrantyFixture(
          items: [
            {
              ...record(),
              'purchasedOn': '2026-10-27',
              'warrantyExpiresOn': '2026-10-26',
            },
          ],
        ),
      ),
      throwsFormatException,
    );
  });
  for (final override in <Map<String, Object?>>[
    {'asOf': '2026-02-29'},
    {'asOf': '2026-10-26\n'},
    {'asOf': null},
    {'through': '2026-11-24'},
    {'through': null},
    {'warranty': 'expired'},
    {'nextOffset': 50},
    {'nextOffset': '50'},
    {'items': null},
    {'ownerId': 'private'},
  ]) {
    test('rejects malformed echo/shape $override', () {
      expect(
        () => parse({...warrantyFixture(), ...override}),
        throwsFormatException,
      );
    });
  }
  test('refuses changed calendar across pages and invalid offsets', () {
    expect(
      () => parse(warrantyFixture(), day: '2026-10-25'),
      throwsFormatException,
    );
    for (final offset in [-1, 100001, 50]) {
      expect(
        () => parse(warrantyFixture(), offset: offset),
        throwsFormatException,
      );
    }
  });
  test('verifies complete records, unique IDs and exact continuation', () {
    final rows = List.generate(
      50,
      (i) => {
        ...record(i),
        'purchasedOn': null,
        'warrantyExpiresOn': '2026-10-26',
      },
    );
    expect(
      parse(
        warrantyFixture(items: rows, next: 100),
        day: '2026-10-26',
        offset: 50,
      ).nextOffset,
      100,
    );
    for (final items in <List<Object?>>[
      [...rows, rows.first],
      [rows.first, rows.first],
      [
        {...rows.first}..remove('purchasedOn'),
      ],
      [
        {...rows.first, 'ownerId': 'private'},
      ],
      [
        {...rows.first, 'version': 0},
      ],
      ['bad item'],
    ]) {
      expect(() => parse(warrantyFixture(items: items)), throwsFormatException);
    }
    expect(
      () => parse(warrantyFixture(items: rows, next: 100)),
      throwsFormatException,
    );
  });
}

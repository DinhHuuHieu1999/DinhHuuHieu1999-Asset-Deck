import 'package:asset_desk/api/asset_location.dart';
import 'package:flutter_test/flutter_test.dart';

import 'asset_test.dart' show record;
import 'asset_warranty_test.dart' show warrantyFixture;

const locationId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
void main() {
  for (final label in [
    null,
    'Office',
    'Kho thiết bị',
    'Room 🧰',
    '%_room',
    'x' * 120,
  ]) {
    test(
      'accepts location $label',
      () => expect(normalizeAssetLocation(label), label),
    );
  }
  for (final label in <Object?>[
    '',
    ' ',
    1,
    false,
    [],
    {},
    'x' * 121,
    'Room\nA',
    'Room\tA',
    'Room\u0000A',
    'Room\u007fA',
    '\ud800',
    '\udfff',
  ]) {
    test(
      'refuses invalid location $label',
      () => expect(() => normalizeAssetLocation(label), throwsFormatException),
    );
  }
  test(
    'replacement normalizes labels but server responses must be canonical',
    () {
      const original = AssetLocation(
        id: locationId,
        version: 2,
        location: null,
      );
      expect(original.replacement(' Room A '), {
        'version': 2,
        'location': 'Room A',
      });
      expect(original.replacement(null), {'version': 2, 'location': null});
      expect(
        () => AssetLocation.fromJson({
          'id': locationId,
          'version': 1,
          'location': ' A ',
        }),
        throwsFormatException,
      );
    },
  );
  test('rejects missing, extra, malformed identity and saturated versions', () {
    for (final value in [
      {'id': locationId, 'version': 1},
      {'id': '../other', 'version': 1, 'location': null},
      {'id': locationId, 'version': 0, 'location': null},
      {'id': locationId, 'version': 1, 'location': null, 'owner': 'other'},
    ])
      expect(() => AssetLocation.fromJson(value), throwsFormatException);
    expect(
      () => const AssetLocation(
        id: locationId,
        version: 2147483647,
        location: null,
      ).replacement('A'),
      throwsFormatException,
    );
  });
  test(
    'location page preserves legacy records and requires explicit location',
    () {
      final row = {...record(), 'location': 'Office'};
      final page = AssetLocationPage.fromJson({
        'items': [row],
        'nextOffset': null,
      }, offset: 0);
      expect(page.items.single.location, 'Office');
      expect(page.items.single.asset.id, row['id']);
      expect(
        () => AssetLocationPage.fromJson({
          'items': [record()],
          'nextOffset': null,
        }, offset: 0),
        throwsFormatException,
      );
      expect(
        () => AssetLocationPage.fromJson({
          'items': [row, row],
          'nextOffset': null,
        }, offset: 0),
        throwsFormatException,
      );
    },
  );
  test('combined warranty pages retain dates and validate echoed horizon', () {
    final fixture = warrantyFixture();
    final rows = (fixture['items'] as List)
        .map((row) => {...row as Map<String, Object?>, 'location': 'Office'})
        .toList();
    final input = {...fixture, 'items': rows};
    final page = AssetLocationPage.fromJson(
      input,
      offset: 0,
      warranty: 'expiring_soon',
    );
    expect(page.warrantyPage!.asOf, '2026-10-26');
    expect(page.items.single.location, 'Office');
    expect(
      () => AssetLocationPage.fromJson(
        {...input, 'through': '2026-11-24'},
        offset: 0,
        warranty: 'expiring_soon',
      ),
      throwsFormatException,
    );
    expect(
      () => AssetLocationPage.fromJson(input, offset: 0),
      throwsFormatException,
    );
  });
}

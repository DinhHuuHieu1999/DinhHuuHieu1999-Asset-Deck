import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset.dart';

Map<String, Object?> record([int index = 0]) => {
  'id': '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
  'name': 'Laptop',
  'category': 'Computers',
  'serial': '',
  'status': 'in_use',
  'notes': '',
  'version': 1,
  'createdAt': '2026-10-25T00:00:00Z',
  'updatedAt': '2026-10-25T00:00:00Z',
};

void main() {
  test('input trims edges without adding identity or ownership', () {
    final json = const AssetInput(
      name: ' Laptop ',
      category: ' Computers ',
      serial: ' X ',
      status: 'stored',
      notes: ' note ',
    ).toJson();
    expect(json, {
      'name': 'Laptop',
      'category': 'Computers',
      'serial': 'X',
      'status': 'stored',
      'notes': 'note',
    });
  });
  for (final status in assetStatuses) {
    test('accepts status $status', () {
      expect(
        AssetInput(name: 'A', category: 'B', status: status).toJson()['status'],
        status,
      );
    });
  }
  for (final input in [
    const AssetInput(name: ' ', category: 'B', status: 'stored'),
    const AssetInput(name: 'A', category: ' ', status: 'stored'),
    const AssetInput(name: 'A', category: 'B', status: 'unknown'),
    const AssetInput(name: 'A\u0000', category: 'B', status: 'stored'),
    AssetInput(name: 'x' * 121, category: 'B', status: 'stored'),
    AssetInput(name: 'A', category: 'x' * 65, status: 'stored'),
    AssetInput(name: 'A', category: 'B', serial: 'x' * 121, status: 'stored'),
    AssetInput(name: 'A', category: 'B', notes: 'x' * 2001, status: 'stored'),
  ]) {
    test(
      'rejects invalid input ${input.name.length}/${input.category.length}/${input.serial.length}/${input.notes.length}/${input.status}',
      () {
        expect(input.toJson, throwsFormatException);
      },
    );
  }
  test('allows inclusive field limits and inert text', () {
    expect(
      AssetInput(
        name: 'x' * 120,
        category: 'x' * 64,
        serial: 'x' * 120,
        notes: 'x' * 2000,
        status: 'repair',
      ).toJson()['notes'],
      hasLength(2000),
    );
    expect(
      const AssetInput(
        name: '%_ https://example.com',
        category: 'B',
        status: 'retired',
      ).toJson()['name'],
      '%_ https://example.com',
    );
  });
  test('parses record with UTC metadata', () {
    expect(AssetRecord.fromJson(record()).version, 1);
  });
  for (final entry in <String, Object?>{
    'id': 'bad',
    'version': 0,
    'createdAt': 'not a date',
    'updatedAt': '2026-10-25',
    'name': null,
  }.entries) {
    test('rejects malformed ${entry.key}', () {
      expect(
        () => AssetRecord.fromJson({...record(), entry.key: entry.value}),
        throwsFormatException,
      );
    });
  }
  test('empty page and immutable records', () {
    final page = AssetPage.fromJson({
      'items': <Object?>[],
      'nextOffset': null,
    }, offset: 0);
    expect(page.items, isEmpty);
    expect(() => page.items.clear(), throwsUnsupportedError);
  });
  test('validates continuation against requested offset', () {
    final records = List.generate(50, record);
    expect(
      AssetPage.fromJson({
        'items': records,
        'nextOffset': 100,
      }, offset: 50).nextOffset,
      100,
    );
    expect(
      () =>
          AssetPage.fromJson({'items': records, 'nextOffset': 50}, offset: 50),
      throwsFormatException,
    );
  });
  test('rejects duplicate identities and partial continuation', () {
    expect(
      () => AssetPage.fromJson({
        'items': [record(), record()],
        'nextOffset': null,
      }, offset: 0),
      throwsFormatException,
    );
    expect(
      () => AssetPage.fromJson({
        'items': [record()],
        'nextOffset': 50,
      }, offset: 0),
      throwsFormatException,
    );
  });
  test('rejects missing continuation, oversized pages and offset overflow', () {
    expect(
      () => AssetPage.fromJson({'items': <Object?>[]}, offset: 0),
      throwsFormatException,
    );
    expect(
      () => AssetPage.fromJson({
        'items': List.generate(51, record),
        'nextOffset': null,
      }, offset: 0),
      throwsFormatException,
    );
    expect(
      () => AssetPage.fromJson({
        'items': <Object?>[],
        'nextOffset': null,
      }, offset: 100001),
      throwsFormatException,
    );
  });
}

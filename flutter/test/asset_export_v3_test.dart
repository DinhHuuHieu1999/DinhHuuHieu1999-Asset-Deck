import 'dart:convert';

import 'package:asset_desk/api/asset_export.dart';
import 'package:asset_desk/api/asset_export_v3.dart';
import 'package:asset_desk/api/strict_export_json.dart';
import 'package:flutter_test/flutter_test.dart';

import 'asset_test.dart' show record;

Map<String, Object?> exportV3Fixture({int count = 1}) => {
  'format': 'asset-desk-inventory',
  'schemaVersion': 3,
  'payload': jsonEncode({
    'exportedAt': '2026-10-26T08:00:00Z',
    'complete': true,
    'recordCount': count,
    'records': List.generate(
      count,
      (i) => {
        ...record(i),
        'notes': 'Unicode: \u4e2d \ud83d\ude80',
        'purchasedOn': '2024-02-29',
        'warrantyExpiresOn': '2026-10-26',
        'location': 'Room %_1',
      },
    ),
  }),
  'sha256': 'a' * 64,
};

void main() {
  Future<AssetExportV3> parse(Map<String, Object?> value) =>
      AssetExportV3.parse(value, digest: (_) async => 'a' * 64);
  Map<String, Object?> patchPayload(Map<String, Object?> patch) {
    final value = exportV3Fixture();
    final payload =
        jsonDecode(value['payload']! as String) as Map<String, Object?>;
    value['payload'] = jsonEncode({...payload, ...patch});
    return value;
  }

  Map<String, Object?> patchRecord(
    Map<String, Object?> patch, {
    String? remove,
  }) {
    final row = {
      ...record(),
      'purchasedOn': '2024-02-29',
      'warrantyExpiresOn': '2026-10-26',
      'location': 'Room %_1',
      ...patch,
    };
    if (remove != null) row.remove(remove);
    return patchPayload({
      'records': [row],
    });
  }

  test('preserves explicit null location and rejects noncanonical or missing location', () async {
    final snapshot = await parse(patchRecord({'location': null}));
    expect(snapshot.records.single.location, isNull);
    for (final location in ['', ' room ', 'x' * 121, 'a\nb', '\ud800', 1]) {
      await expectLater(
        parse(patchRecord({'location': location})),
        throwsFormatException,
      );
    }
    await expectLater(
      parse(patchRecord({}, remove: 'location')),
      throwsFormatException,
    );
    final valid = await parse(exportV3Fixture());
    expect(valid.records.single.location, 'Room %_1');
    final legacy = exportV3Fixture()..['schemaVersion'] = 2;
    await expectLater(parse(legacy), throwsFormatException);
  });

  for (final count in [0, 1, 51, 500]) {
    test('v3 validates $count complete records without mutation', () async {
      final fixture = exportV3Fixture(count: count);
      final before = jsonEncode(fixture);
      final snapshot = await parse(fixture);
      expect(snapshot.count, count);
      expect(jsonEncode(fixture), before);
      expect(() => snapshot.records.clear(), throwsUnsupportedError);
      if (count > 0) {
        expect(snapshot.records.first.dates.purchasedOn, '2024-02-29');
        expect(snapshot.records.first.dates.warrantyExpiresOn, '2026-10-26');
      }
    });
  }
  test(
    'digest sees exact original UTF-8 payload, including whitespace',
    () async {
      final value = exportV3Fixture();
      value['payload'] = ' \n${value['payload']}\t';
      var calls = 0;
      final snapshot = await AssetExportV3.parse(
        value,
        digest: (bytes) async {
          calls++;
          expect(utf8.decode(bytes), value['payload']);
          return 'a' * 64;
        },
      );
      expect(calls, 1);
      expect(
        snapshot.records.single.asset.input.notes,
        'Unicode: \u4e2d \ud83d\ude80',
      );
      expect(jsonDecode(snapshot.json), value);
    },
  );
  for (final pair in [
    [null, null],
    [null, '9999-12-31'],
    ['0001-01-01', null],
    ['2024-02-29', '2024-02-29'],
  ]) {
    test('nullable/equal/extreme dates are preserved: $pair', () async {
      final value = await parse(
        patchRecord({'purchasedOn': pair[0], 'warrantyExpiresOn': pair[1]}),
      );
      expect(value.records.single.dates.purchasedOn, pair[0]);
      expect(value.records.single.dates.warrantyExpiresOn, pair[1]);
    });
  }
  for (final patch in <Map<String, Object?>>[
    {'format': 'other'},
    {'schemaVersion': 1},
    {'schemaVersion': 3.0},
    {'payload': null},
    {'sha256': 'A' * 64},
    {'extra': 'private'},
  ]) {
    test('rejects envelope $patch before digest', () async {
      await expectLater(
        AssetExportV3.parse({
          ...exportV3Fixture(),
          ...patch,
        }, digest: (_) async => throw StateError('must not run')),
        throwsFormatException,
      );
    });
  }
  for (final patch in <Map<String, Object?>>[
    {'complete': false},
    {'recordCount': 0},
    {'recordCount': 1.0},
    {'records': null},
    {'exportedAt': 'invalid'},
    {'exportedAt': '2026-10-26T08:00:00'},
    {'extra': 'private'},
  ]) {
    test('rejects incomplete/malformed snapshot $patch', () async {
      await expectLater(parse(patchPayload(patch)), throwsFormatException);
    });
  }
  for (final patch in <Map<String, Object?>>[
    {'purchasedOn': '2023-02-29'},
    {'purchasedOn': '0000-01-01'},
    {'purchasedOn': '2024-02-29\n'},
    {'purchasedOn': 20240229},
    {'warrantyExpiresOn': '2020-01-01'},
    {'warrantyExpiresOn': false},
    {'warrantyExpiresOn': '2026-10-26T00:00:00Z'},
    {'owner_id': 'private'},
    {'name': null},
    {'status': 'unknown'},
    {'version': 0},
  ]) {
    test('rejects invalid record $patch', () async {
      await expectLater(parse(patchRecord(patch)), throwsFormatException);
    });
  }
  for (final field in ['purchasedOn', 'warrantyExpiresOn', 'notes', 'id']) {
    test('requires explicit $field', () async {
      await expectLater(
        parse(patchRecord({}, remove: field)),
        throwsFormatException,
      );
    });
  }
  test('rejects duplicate identities regardless of case', () async {
    final row = {...record(), 'purchasedOn': null, 'warrantyExpiresOn': null};
    await expectLater(
      parse(
        patchPayload({
          'recordCount': 2,
          'records': [row, row],
        }),
      ),
      throwsFormatException,
    );
  });
  test('rejects 501 records and oversized UTF-8 envelope', () async {
    await expectLater(
      parse(exportV3Fixture(count: 501)),
      throwsFormatException,
    );
    final value = exportV3Fixture();
    value['payload'] = ' ' * (1024 * 1024);
    await expectLater(parse(value), throwsFormatException);
  });
  test('rejects duplicate JSON keys before SDK decoding loses them', () async {
    final value = exportV3Fixture();
    value['payload'] = (value['payload']! as String).replaceFirst(
      '"complete":true',
      '"complete":true,"complete":true',
    );
    await expectLater(parse(value), throwsFormatException);
    expect(
      () => decodeAssetExportJson('{"schemaVersion":2,"schemaVersion":2}'),
      throwsFormatException,
    );
  });
  test(
    'checksum mismatch or native failure cannot return a snapshot',
    () async {
      await expectLater(
        AssetExportV3.parse(exportV3Fixture(), digest: (_) async => 'b' * 64),
        throwsFormatException,
      );
      await expectLater(
        AssetExportV3.parse(
          exportV3Fixture(),
          digest: (_) async => throw StateError('synthetic'),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'v1 parser refuses v3 rather than silently dropping date fields',
    () async {
      await expectLater(
        AssetExport.parse(exportV3Fixture(), digest: (_) async => 'a' * 64),
        throwsFormatException,
      );
    },
  );
}

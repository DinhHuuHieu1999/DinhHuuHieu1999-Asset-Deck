import 'dart:convert';
import 'dart:io';

import 'package:asset_desk/api/asset_export.dart';
import 'package:asset_desk/api/strict_export_json.dart';
import 'package:flutter_test/flutter_test.dart';

import 'asset_test.dart' show record;

void main() {
  Map<String, Object?> envelope({int count = 1}) => {
    'format': 'asset-desk-inventory',
    'schemaVersion': 1,
    'payload': jsonEncode({
      'exportedAt': '2026-10-25T08:00:00Z',
      'complete': true,
      'recordCount': count,
      'records': List.generate(count, record),
    }),
    'sha256': 'a' * 64,
  };
  Future<AssetExport> parse(Map<String, Object?> value) =>
      AssetExport.parse(value, digest: (_) async => 'a' * 64);
  Map<String, Object?> payloadPatch(Map<String, Object?> patch) {
    final value = envelope();
    final payload =
        jsonDecode(value['payload']! as String) as Map<String, Object?>;
    value['payload'] = jsonEncode({...payload, ...patch});
    return value;
  }

  for (final count in [0, 1, 51, 500]) {
    test(
      'validates $count complete records and makes them immutable',
      () async {
        final value = await parse(envelope(count: count));
        expect(value.count, count);
        expect(() => value.records.clear(), throwsUnsupportedError);
      },
    );
  }
  test('passes exact Unicode payload bytes to digest callback', () async {
    final fixture = jsonDecode(
      File('test/fixtures/inventory-export-v1.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final expectedPayload = fixture['payload']! as String;
    var calls = 0;
    final value = await AssetExport.parse(
      fixture,
      digest: (bytes) async {
        calls++;
        expect(utf8.decode(bytes), expectedPayload);
        return fixture['sha256']! as String;
      },
    );
    expect(calls, 1);
    expect(
      value.records.single.input.notes,
      'Unicode: \u00e9 \u4e2d \ud83d\ude80',
    );
    // Digest callback is mocked here; this does not certify native BCrypt.
  });
  test(
    'rejects mismatch and propagates digest failure without returning data',
    () async {
      await expectLater(
        AssetExport.parse(envelope(), digest: (_) async => 'b' * 64),
        throwsFormatException,
      );
      await expectLater(
        AssetExport.parse(
          envelope(),
          digest: (_) async => throw StateError('synthetic'),
        ),
        throwsStateError,
      );
    },
  );
  for (final patch in <Map<String, Object?>>[
    {'format': 'other'},
    {'schemaVersion': 2},
    {'schemaVersion': 1.0},
    {'payload': null},
    {'sha256': 'A' * 64},
    {'extra': 'field'},
  ]) {
    test('rejects envelope $patch before invoking native digest', () async {
      await expectLater(
        AssetExport.parse({
          ...envelope(),
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
    {'exportedAt': 'not a date'},
    {'exportedAt': '2026-10-25T08:00:00'},
    {'extra': 'field'},
    {
      'records': [record(), record()],
      'recordCount': 2,
    },
    {
      'records': [
        {...record(), 'ownerId': 'private'},
      ],
    },
    {
      'records': [
        {...record(), 'status': 'unknown'},
      ],
    },
  ]) {
    test('rejects inconsistent payload $patch', () async {
      await expectLater(parse(payloadPatch(patch)), throwsFormatException);
    });
  }
  test('rejects record and UTF-8 byte overflow', () async {
    await expectLater(parse(envelope(count: 501)), throwsFormatException);
    await expectLater(
      parse(payloadPatch({'extra': '\u4e2d' * (400 * 1024)})),
      throwsFormatException,
    );
  });
  test(
    'rejects duplicate escaped keys and deep nesting before SDK decoding',
    () {
      expect(
        () => decodeAssetExportJson(r'{"name":1,"n\u0061me":2}'),
        throwsFormatException,
      );
      expect(
        () => decodeAssetExportJson('[' * 70 + '0' + ']' * 70),
        throwsFormatException,
      );
      expect(
        () => decodeAssetExportJson(r'{"name":"\ud800"}'),
        throwsFormatException,
      );
    },
  );
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset_selection_export.dart';
import 'package:asset_desk/api/asset_export_v3.dart';

import 'asset_export_v3_test.dart' show exportV3Fixture;

Map<String, Object?> selectionFixture({int count = 1}) {
  final full = jsonDecode(
    exportV3Fixture(count: count)['payload']! as String,
  ) as Map<String, Object?>;
  return {
    'format': 'asset-desk-inventory-selection',
    'schemaVersion': 1,
    'sha256': 'a' * 64,
    'payload': jsonEncode({
      'exportedAt': full['exportedAt'],
      'scope': 'filtered-selection',
      'allMatchesIncluded': true,
      'filters': {
        'q': '%_',
        'status': 'stored',
        'category': 'fixture',
        'locationMode': 'exact',
        'location': 'Room %_1',
        'sort': 'name_asc',
        'warranty': null,
      },
      'recordCount': full['recordCount'],
      'records': full['records'],
    }),
  };
}

void main() {
  Future<AssetSelectionExport> parse(Map<String, Object?> value) =>
      AssetSelectionExport.parse(value, digest: (_) async => 'a' * 64);
  for (final count in [0, 51, 500]) {
    test('accepts every record in a bounded $count-record selection', () async {
      final snapshot = await parse(selectionFixture(count: count));
      expect(snapshot.count, count);
      expect(snapshot.records.map((row) => row.asset.id).toSet().length, count);
    });
  }
  test('rejects 501 records before computing any checksum', () async {
    var called = false;
    await expectLater(
      AssetSelectionExport.parse(
        selectionFixture(count: 501),
        digest: (_) async {
          called = true;
          return 'a' * 64;
        },
      ),
      throwsFormatException,
    );
    expect(called, false);
  });
  test(
    'rejects UTF-8 byte overflow before checksum or record parsing',
    () async {
      final value = selectionFixture();
      value['payload'] = '\u754c' * (350 * 1024);
      var called = false;
      await expectLater(
        AssetSelectionExport.parse(
          value,
          digest: (_) async {
            called = true;
            return 'a' * 64;
          },
        ),
        throwsFormatException,
      );
      expect(called, false);
    },
  );
  test('rejects duplicate payload keys and duplicate record IDs', () async {
    final duplicateKeys = selectionFixture();
    duplicateKeys['payload'] = (duplicateKeys['payload']! as String)
        .replaceFirst('"recordCount":1', '"recordCount":1,"recordCount":1');
    await expectLater(parse(duplicateKeys), throwsFormatException);
    final value = selectionFixture(count: 2);
    final payload =
        jsonDecode(value['payload']! as String) as Map<String, Object?>;
    final rows = payload['records']! as List;
    rows[1] = rows[0];
    value['payload'] = jsonEncode(payload);
    await expectLater(parse(value), throwsFormatException);
  });
  test('hashes exact payload bytes without trimming or re-encoding', () async {
    final value = selectionFixture();
    final exact = ' \n${value['payload']}\t';
    value['payload'] = exact;
    String? seen;
    await AssetSelectionExport.parse(
      value,
      digest: (bytes) async {
        seen = utf8.decode(bytes);
        return 'a' * 64;
      },
    );
    expect(seen, exact);
  });
  test('valid selection is immutable and distinct from full export', () async {
    final value = selectionFixture();
    final result = await parse(value);
    expect(result.count, 1);
    expect(result.records.single.location, 'Room %_1');
    expect(result.scope.filters['q'], '%_');
    expect(() => result.scope.filters.clear(), throwsUnsupportedError);
    expect(() => result.records.clear(), throwsUnsupportedError);
    await expectLater(
      AssetExportV3.parse(value, digest: (_) async => 'a' * 64),
      throwsFormatException,
    );
    await expectLater(parse(exportV3Fixture()), throwsFormatException);
  });
  for (final patch in <Map<String, Object?>>[
    {'complete': true},
    {'allMatchesIncluded': false},
    {'recordCount': 2},
    {'records': []},
    {'scope': 'full-inventory'},
    {'filters': {}},
  ]) {
    test('rejects inconsistent snapshot $patch', () async {
      final value = selectionFixture();
      final payload =
          jsonDecode(value['payload']! as String) as Map<String, Object?>;
      value['payload'] = jsonEncode({...payload, ...patch});
      await expectLater(parse(value), throwsFormatException);
    });
  }
  test('rejects mismatch and digest failure', () async {
    await expectLater(
      AssetSelectionExport.parse(
        selectionFixture(),
        digest: (_) async => 'b' * 64,
      ),
      throwsFormatException,
    );
    await expectLater(
      AssetSelectionExport.parse(
        selectionFixture(),
        digest: (_) async => throw StateError('synthetic'),
      ),
      throwsStateError,
    );
  });
  test(
    'requires canonical exact labels and explicit bounded warranty date',
    () {
      final payload = jsonDecode(
        selectionFixture()['payload']! as String,
      ) as Map<String, Object?>;
      final filters = payload['filters']! as Map<String, Object?>;
      for (final patch in [
        {'location': null},
        {'sort': 'unsafe'},
        {'q': ' x '},
        {
          'warranty': {'filter': 'expired', 'asOf': '', 'through': ''},
        },
      ]) {
        expect(
          () => AssetSelectionScope.fromJson({...filters, ...patch}),
          throwsFormatException,
        );
      }
    },
  );
}

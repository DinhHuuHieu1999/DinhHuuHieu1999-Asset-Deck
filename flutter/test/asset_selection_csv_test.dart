import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset_selection_csv.dart';
import 'package:asset_desk/api/asset_selection_export_v2.dart';

import 'asset_selection_export_v2_test.dart' show selectionV2Fixture;

void main() {
  Future<AssetSelectionCsv> convert({int count = 1, String? notes}) async {
    final envelope = selectionV2Fixture(count: count, date: '2024-02-29');
    if (notes != null) {
      final body = jsonDecode(envelope['payload']! as String) as Map;
      for (final row in body['records'] as List) {
        (row as Map)['notes'] = notes;
      }
      envelope['payload'] = jsonEncode(body);
    }
    final snapshot = await AssetSelectionExportV2.parse(
      envelope,
      digest: (_) async => 'a' * 64,
    );
    return AssetSelectionCsv.fromSelection(snapshot);
  }

  for (final count in [0, 1, 51, 500]) {
    test('complete selection $count rows, fixed header and CRLF', () async {
      final csv = await convert(count: count);
      expect(csv.count, count);
      expect(csv.text.split('\r\n').length, count + 2);
      expect(csv.text.startsWith('"id","name","category","serial"'), isTrue);
      expect(csv.text.startsWith('\ufeff'), isFalse);
    });
  }
  test('quotes commas, double quotes, Unicode and embedded newlines', () async {
    final csv = await convert(notes: 'Thiết bị, "A"\nsecond line');
    expect(csv.text, contains('"Thiết bị, ""A""\nsecond line"'));
    expect(csv.text, contains('"2024-02-29"'));
    expect(utf8.decode(csv.bytes), csv.text);
    final bytes = csv.bytes;
    bytes[0] = 0;
    expect(csv.bytes[0], 34);
  });
  for (final value in [
    '=1+1',
    '+SUM(A1)',
    '-1+1',
    '@SUM(A1)',
    '  =1',
    '\t=1',
    '\r=1',
    '\n=1',
    '＝1',
    '\u00a0+1',
  ]) {
    test('protects formula-like cell ${jsonEncode(value)}', () async {
      final csv = await convert(notes: value);
      expect(csv.text, contains('"\'$value"'));
      expect(csv.protectedCells, greaterThanOrEqualTo(1));
    });
  }
  test('normal percent and underscore text stays literal', () async {
    final csv = await convert(notes: 'Synthetic room %_1');
    expect(csv.text, contains('"Synthetic room %_1"'));
    expect(csv.text, isNot(contains('"\'Synthetic room %_1"')));
  });
}

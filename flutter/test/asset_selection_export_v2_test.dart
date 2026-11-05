import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset_selection_export_v2.dart';

import 'asset_selection_export_test.dart' show selectionFixture;

Map<String, Object?> selectionV2Fixture({
  int count = 1,
  String mode = 'all',
  String? date,
}) {
  final envelope = selectionFixture(count: count);
  final body =
      jsonDecode(envelope['payload']! as String) as Map<String, Object?>;
  (body['filters'] as Map<String, dynamic>)['check'] = {
    'mode': mode,
    if (mode == 'before' || mode == 'on_or_after') 'cutoff': '2024-03-01',
  };
  for (final row in body['records']! as List) {
    (row as Map)['lastCheckedDate'] = date;
  }
  return {...envelope, 'schemaVersion': 2, 'payload': jsonEncode(body)};
}

void main() {
  Future<AssetSelectionExportV2> parse(Map<String, Object?> value) =>
      AssetSelectionExportV2.parse(value, digest: (_) async => 'a' * 64);
  for (final count in [0, 1, 51, 500]) {
    test('accepts complete $count record v2 snapshot', () async {
      final result = await parse(selectionV2Fixture(count: count));
      expect(result.count, count);
      expect(result.scope.toQuery()['checkMode'], 'all');
      expect(() => result.records.clear(), throwsUnsupportedError);
    });
  }
  for (final mode in ['unknown', 'before', 'on_or_after']) {
    test('retains explicit $mode scope and dates', () async {
      final date = mode == 'unknown'
          ? null
          : mode == 'before'
          ? '2024-02-29'
          : '2024-03-01';
      final result = await parse(selectionV2Fixture(mode: mode, date: date));
      expect(result.records.single.lastCheckedDate, date);
      expect(result.scope.toQuery()['checkMode'], mode);
    });
  }
  test('rejects mismatch and invalid calendar dates', () async {
    for (final v in [
      selectionV2Fixture(mode: 'before', date: '2024-03-01'),
      selectionV2Fixture(mode: 'on_or_after'),
      selectionV2Fixture(date: '2023-02-29'),
    ]) {
      await expectLater(parse(v), throwsFormatException);
    }
  });
  test('rejects old envelope, checksum mismatch and overflow', () async {
    await expectLater(parse(selectionFixture()), throwsFormatException);
    await expectLater(
      parse(selectionV2Fixture(count: 501)),
      throwsFormatException,
    );
    await expectLater(
      AssetSelectionExportV2.parse(
        selectionV2Fixture(),
        digest: (_) async => 'b' * 64,
      ),
      throwsFormatException,
    );
  });
  test('validates exact check tag and immutable scope', () {
    final base =
        jsonDecode(selectionV2Fixture()['payload']! as String)['filters']
            as Map<String, dynamic>;
    for (final check in [
      {'mode': 'all', 'cutoff': '2024-03-01'},
      {'mode': 'before'},
      {'mode': 'unknown', 'extra': true},
      {'mode': 'before', 'cutoff': '2023-02-29'},
    ]) {
      expect(
        () => AssetSelectionScopeV2.fromJson({...base, 'check': check}),
        throwsFormatException,
      );
    }
    final scope = AssetSelectionScopeV2.fromJson(base);
    expect(() => scope.check['mode'] = 'before', throwsUnsupportedError);
  });
}

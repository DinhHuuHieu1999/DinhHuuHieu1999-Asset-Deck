import 'dart:convert';

import 'package:asset_desk/api/asset_export_v2.dart';
import 'package:asset_desk/api/asset_import.dart';
import 'package:asset_desk/api/asset_import_v2.dart';
import 'package:asset_desk/api/asset_import_recovery.dart';
import 'package:asset_desk/api/asset_import_v2_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

import 'asset_export_v2_test.dart' show exportV2Fixture;

void main() {
  const owner = 'abcdef0123456789abcdef01';
  const key = '12345678-1234-4123-8123-123456789abc';
  const api = 'https://localhost:28443/api/v1';
  final row = <String, Object?>{
    'name': 'Laptop',
    'category': 'test',
    'serial': '',
    'status': 'stored',
    'notes': '',
    'purchasedOn': null,
    'warrantyExpiresOn': null,
  };
  AssetImportV2Draft restore(Map<String, Object?> record) =>
      AssetImportV2Draft.restore(
        accountId: owner,
        requestJson: jsonEncode({
          'requestId': key,
          'records': [record],
        }),
      );

  test('prepare verified v2 strips metadata while retaining dates', () async {
    final snapshot = await AssetExportV2.parse(
      exportV2Fixture(),
      digest: (_) async => 'a' * 64,
    );
    final draft = AssetImportV2Draft.prepare(
      snapshot: snapshot,
      accountId: owner.toUpperCase(),
      requestId: key.toUpperCase(),
    );
    expect(draft.accountId, owner);
    expect(draft.requestId, key);
    expect(draft.records.single.keys, [
      'name',
      'category',
      'serial',
      'status',
      'notes',
      'purchasedOn',
      'warrantyExpiresOn',
    ]);
    expect(draft.records.single['purchasedOn'], '2024-02-29');
    expect(draft.records.single['warrantyExpiresOn'], '2026-10-26');
    expect(() => draft.records.clear(), throwsUnsupportedError);
    expect(
      () => draft.records.single['purchasedOn'] = null,
      throwsUnsupportedError,
    );
  });
  test('requires both date keys and rejects malformed or reversed dates', () {
    final missing = {...row}..remove('purchasedOn');
    for (final record in [
      missing,
      {...row, 'purchasedOn': 1},
      {...row, 'purchasedOn': '1900-02-29'},
      {...row, 'purchasedOn': '2024-01-02', 'warrantyExpiresOn': '2024-01-01'},
      {...row, 'name': ' Laptop '},
    ]) {
      expect(() => restore(record), throwsFormatException);
    }
    expect(restore({...row, 'purchasedOn': '2000-02-29'}).count, 1);
  });
  test('v1 and v2 request decoders refuse each other', () {
    final v2 = restore(row);
    expect(
      () => AssetImportDraft.restore(accountId: owner, requestJson: v2.json),
      throwsFormatException,
    );
    final v1 = {...row}
      ..remove('purchasedOn')
      ..remove('warrantyExpiresOn');
    expect(() => restore(v1), throwsFormatException);
  });
  test('recovery is version-separated and requires exact operation', () async {
    final file = await AssetImportV2Recovery.prepare(
      draft: restore(row),
      apiBase: api,
      digest: (_) async => 'a' * 64,
    );
    await expectLater(
      AssetImportRecovery.parse(
        file.json,
        currentApiBase: api,
        currentAccountId: owner,
        digest: (_) async => 'a' * 64,
      ),
      throwsFormatException,
    );
    final envelope = jsonDecode(file.json) as Map<String, dynamic>;
    final payload =
        jsonDecode(envelope['payload'] as String) as Map<String, dynamic>;
    expect(payload['operation'], 'inventory-add-only-v2');
    payload['operation'] = 'inventory-add-only-v1';
    envelope['payload'] = jsonEncode(payload);
    await expectLater(
      AssetImportV2Recovery.parse(
        jsonEncode(envelope),
        currentApiBase: api,
        currentAccountId: owner,
        digest: (_) async => 'a' * 64,
      ),
      throwsFormatException,
    );
    envelope['schemaVersion'] = 1;
    await expectLater(
      AssetImportV2Recovery.parse(
        jsonEncode(envelope),
        currentApiBase: api,
        currentAccountId: owner,
        digest: (_) async => 'a' * 64,
      ),
      throwsFormatException,
    );
  });
}

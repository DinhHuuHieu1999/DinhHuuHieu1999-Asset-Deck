import 'package:asset_desk/api/asset_import_v2_recovery.dart';
import 'package:asset_desk/api/asset_import_v2.dart';

import 'dart:convert';

import 'package:asset_desk/api/asset_export_v3.dart';
import 'package:asset_desk/api/asset_import.dart';
import 'package:asset_desk/api/asset_import_v3.dart';
import 'package:asset_desk/api/asset_import_recovery.dart';
import 'package:asset_desk/api/asset_import_v3_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

import 'asset_export_v3_test.dart' show exportV3Fixture;

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
    'location': null,
  };
  AssetImportV3Draft restore(Map<String, Object?> record) =>
      AssetImportV3Draft.restore(
        accountId: owner,
        requestJson: jsonEncode({
          'requestId': key,
          'records': [record],
        }),
      );

  test('prepare verified v3 strips metadata while retaining dates', () async {
    final snapshot = await AssetExportV3.parse(
      exportV3Fixture(),
      digest: (_) async => 'a' * 64,
    );
    final draft = AssetImportV3Draft.prepare(
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
      'location',
    ]);
    expect(draft.records.single['location'], 'Room %_1');
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
  test('v1 and v3 request decoders refuse each other', () {
    final v3 = restore(row);
    expect(
      () => AssetImportDraft.restore(accountId: owner, requestJson: v3.json),
      throwsFormatException,
    );
    final v1 = {...row}
      ..remove('purchasedOn')
      ..remove('warrantyExpiresOn');
    expect(() => restore(v1), throwsFormatException);
  });
  test('recovery is version-separated and requires exact operation', () async {
    final file = await AssetImportV3Recovery.prepare(
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
    expect(payload['operation'], 'inventory-add-only-v3');
    payload['operation'] = 'inventory-add-only-v1';
    envelope['payload'] = jsonEncode(payload);
    await expectLater(
      AssetImportV3Recovery.parse(
        jsonEncode(envelope),
        currentApiBase: api,
        currentAccountId: owner,
        digest: (_) async => 'a' * 64,
      ),
      throwsFormatException,
    );
    envelope['schemaVersion'] = 1;
    await expectLater(
      AssetImportV3Recovery.parse(
        jsonEncode(envelope),
        currentApiBase: api,
        currentAccountId: owner,
        digest: (_) async => 'a' * 64,
      ),
      throwsFormatException,
    );
  });
  test(
    'restore requires canonical nullable location and excludes v2 requests',
    () {
      for (final value in ['', ' room ', 'x' * 121, 'a\nb', '\ud800', 1]) {
        expect(
          () => restore({...row, 'location': value}),
          throwsFormatException,
        );
      }
      expect(
        restore({...row, 'location': 'Room %_1'}).records.single['location'],
        'Room %_1',
      );
      final missing = {...row}..remove('location');
      expect(() => restore(missing), throwsFormatException);
      expect(
        () => AssetImportV2Draft.restore(
          accountId: owner,
          requestJson: restore(row).json,
        ),
        throwsFormatException,
      );
    },
  );
  test('empty verified snapshot cannot create an import draft', () async {
    final empty = await AssetExportV3.parse(
      exportV3Fixture(count: 0),
      digest: (_) async => 'a' * 64,
    );
    expect(
      () => AssetImportV3Draft.prepare(
        snapshot: empty,
        accountId: owner,
        requestId: key,
      ),
      throwsFormatException,
    );
  });
  test(
    'receipt preserves count/key and refuses malformed or duplicate identities',
    () {
      final draft = restore(row);
      final receipt = {
        'requestId': key,
        'recordCount': 1,
        'recordIds': [key.toUpperCase()],
      };
      expect(AssetImportV3Receipt.parse(receipt, draft).recordIds, [key]);
      for (final value in <Object?>[
        null,
        {...receipt, 'requestId': 'other'},
        {...receipt, 'recordCount': true},
        {
          ...receipt,
          'recordIds': ['invalid'],
        },
        {...receipt, 'owner': owner},
      ]) {
        expect(
          () => AssetImportV3Receipt.parse(value, draft),
          throwsFormatException,
        );
      }
      expect(
        () => draft.requireAccount('0123456789abcdef01234567'),
        throwsStateError,
      );
    },
  );
  test('v2 recovery never accepts v3 and v3 never accepts v2', () async {
    final v3 = await AssetImportV3Recovery.prepare(
      draft: restore(row),
      apiBase: api,
      digest: (_) async => 'a' * 64,
    );
    await expectLater(
      AssetImportV2Recovery.parse(
        v3.json,
        currentApiBase: api,
        currentAccountId: owner,
        digest: (_) async => 'a' * 64,
      ),
      throwsFormatException,
    );
    final oldRow = {...row}..remove('location');
    final v2Draft = AssetImportV2Draft.restore(
      accountId: owner,
      requestJson: jsonEncode({
        'requestId': key,
        'records': [oldRow],
      }),
    );
    final v2 = await AssetImportV2Recovery.prepare(
      draft: v2Draft,
      apiBase: api,
      digest: (_) async => 'a' * 64,
    );
    await expectLater(
      AssetImportV3Recovery.parse(
        v2.json,
        currentApiBase: api,
        currentAccountId: owner,
        digest: (_) async => 'a' * 64,
      ),
      throwsFormatException,
    );
  });
}

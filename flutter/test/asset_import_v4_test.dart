import 'package:asset_desk/api/asset_import_v4_recovery.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset_export_v4.dart';
import 'package:asset_desk/api/asset_import_v4.dart';
import 'package:asset_desk/api/asset_import_v3.dart';

import 'asset_export_v4_test.dart' show exportV4Fixture;

void main() {
  const owner = 'abcdef0123456789abcdef01';
  const key = '12345678-1234-4123-8123-123456789abc';
  Future<AssetImportV4Draft> prepare() async => AssetImportV4Draft.prepare(
    snapshot: await AssetExportV4.parse(
      exportV4Fixture(),
      digest: (_) async => 'a' * 64,
    ),
    accountId: owner,
    requestId: key,
  );
  test(
    'verified v4 strips metadata, retains check date and restores exact bytes',
    () async {
      final draft = await prepare();
      expect(draft.records.single.containsKey('id'), false);
      expect(draft.records.single.containsKey('lastCheckedDate'), true);
      final restored = AssetImportV4Draft.restore(
        accountId: owner,
        requestJson: draft.json,
      );
      expect(restored.json, draft.json);
      expect(restored.records, draft.records);
      expect(() => restored.records.clear(), throwsUnsupportedError);
      expect(
        () => restored.records.single['lastCheckedDate'] = null,
        throwsUnsupportedError,
      );
      expect(
        () => restored.requireAccount('bbcdef0123456789abcdef01'),
        throwsStateError,
      );
      expect(
        () => AssetImportV3Draft.restore(
          accountId: owner,
          requestJson: draft.json,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'recovery v4 roundtrip retains exact request and rejects v3 schema',
    () async {
      final draft = await prepare();
      const endpoint = 'https://localhost:29943/api/v1';
      final recovery = await AssetImportV4Recovery.prepare(
        draft: draft,
        apiBase: endpoint,
        digest: (_) async => 'a' * 64,
      );
      final restored = await AssetImportV4Recovery.parse(
        recovery.json,
        currentApiBase: endpoint,
        currentAccountId: owner,
        digest: (_) async => 'a' * 64,
      );
      expect(restored.draft.json, draft.json);
      final invalid = jsonDecode(recovery.json) as Map<String, dynamic>;
      invalid['schemaVersion'] = 3;
      await expectLater(
        AssetImportV4Recovery.parse(
          jsonEncode(invalid),
          currentApiBase: endpoint,
          currentAccountId: owner,
          digest: (_) async => 'a' * 64,
        ),
        throwsFormatException,
      );
    },
  );
  for (final date in [null, '0001-01-01', '9999-12-31']) {
    test('restores literal date $date', () async {
      final draft = await prepare();
      final value = jsonDecode(draft.json) as Map<String, dynamic>;
      value['records'][0]['lastCheckedDate'] = date;
      expect(
        AssetImportV4Draft.restore(
          accountId: owner,
          requestJson: jsonEncode(value),
        ).records.single['lastCheckedDate'],
        date,
      );
    });
  }
  for (final date in ['2023-02-29', '', 42]) {
    test('rejects invalid check date $date', () async {
      final draft = await prepare();
      final value = jsonDecode(draft.json) as Map<String, dynamic>;
      value['records'][0]['lastCheckedDate'] = date;
      expect(
        () => AssetImportV4Draft.restore(
          accountId: owner,
          requestJson: jsonEncode(value),
        ),
        throwsFormatException,
      );
    });
  }
}

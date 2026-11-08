import 'dart:async';

import 'package:asset_desk/api/asset_import_operation.dart';

import 'dart:convert';
import 'dart:io';

import 'package:asset_desk/api/asset_export.dart';
import 'package:asset_desk/api/asset_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const owner = 'abcdef0123456789abcdef01';
  const key = '12345678-1234-4123-8123-123456789ABC';
  late AssetExport snapshot;
  setUp(() async {
    final envelope = jsonDecode(
      File('test/fixtures/inventory-export-v1.json').readAsStringSync(),
    ) as Map<String, Object?>;
    snapshot = await AssetExport.parse(
      envelope,
      digest: (_) async => envelope['sha256']! as String,
    );
  });
  AssetImportDraft prepare({String account = owner, String request = key}) =>
      AssetImportDraft.prepare(
        snapshot: snapshot,
        accountId: account,
        requestId: request,
      );

  Future<AssetExport> alteredSnapshot(
    void Function(Map<String, dynamic>) change,
  ) async {
    final envelope = jsonDecode(
      File('test/fixtures/inventory-export-v1.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final payload =
        jsonDecode(envelope['payload']! as String) as Map<String, dynamic>;
    change(payload);
    envelope['payload'] = jsonEncode(payload);
    // Stubbed checksum isolates draft/record validation; not hash acceptance.
    return AssetExport.parse(
      envelope,
      digest: (_) async => envelope['sha256']! as String,
    );
  }

  test(
    'rejects empty imports even though empty exports can be inspected',
    () async {
      snapshot = await alteredSnapshot((payload) {
        payload['records'] = <Object?>[];
        payload['recordCount'] = 0;
      });
      expect(prepare, throwsFormatException);
    },
  );
  test(
    'rejects unpaired Unicode before creating an import operation',
    () async {
      await expectLater(
        alteredSnapshot((payload) {
          (payload['records'] as List).first['notes'] = String.fromCharCode(
            0xd800,
          );
        }),
        throwsFormatException,
      );
    },
  );
  test('rejects duplicate receipt IDs for a multi-record draft', () async {
    snapshot = await alteredSnapshot((payload) {
      final records = payload['records'] as List;
      records.add({
        ...records.first as Map<String, dynamic>,
        'id': '00000000-0000-4000-8000-000000000002',
      });
      payload['recordCount'] = 2;
    });
    final draft = prepare();
    expect(
      () => AssetImportReceipt.parse({
        'requestId': draft.requestId,
        'recordCount': 2,
        'recordIds': [key, key.toLowerCase()],
      }, draft),
      throwsFormatException,
    );
  });
  test('submits only editable fields and canonical operation key', () {
    final draft = prepare();
    final payload = jsonDecode(draft.json) as Map<String, dynamic>;
    expect(payload.keys, unorderedEquals(['requestId', 'records']));
    expect(payload['requestId'], key.toLowerCase());
    expect(
      draft.records.single.keys,
      unorderedEquals(['name', 'category', 'serial', 'status', 'notes']),
    );
    expect(draft.count, 1);
    expect(draft.json, prepare().json);
  });
  test('is deeply immutable and retains the exact serialized request', () {
    final draft = prepare();
    final original = draft.json;
    expect(() => draft.records.clear(), throwsUnsupportedError);
    expect(
      () => draft.records.single['name'] = 'changed',
      throwsUnsupportedError,
    );
    expect(draft.json, original);
  });
  test('does not retarget a draft to another account', () {
    final draft = prepare(account: owner.toUpperCase());
    draft.requireAccount(owner);
    expect(
      () => draft.requireAccount('000000000000000000000000'),
      throwsStateError,
    );
  });
  test('rejects malformed account and non-v4 request identifiers', () {
    expect(() => prepare(account: ''), throwsFormatException);
    expect(
      () => prepare(request: '12345678-1234-1123-8123-123456789abc'),
      throwsFormatException,
    );
    expect(() => prepare(request: 'invalid'), throwsFormatException);
  });

  test('generates distinct UUID v4 keys locally', () {
    final keys = List.generate(100, (_) => createAssetImportRequestId());
    expect(keys.toSet().length, 100);
    for (final key in keys) {
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(key),
        isTrue,
      );
    }
  });
  test('accepts only an exact matching immutable receipt', () {
    final draft = prepare();
    final body = <String, Object?>{
      'requestId': draft.requestId,
      'recordCount': 1,
      'recordIds': [key],
    };
    final receipt = AssetImportReceipt.parse(body, draft);
    expect(receipt.recordIds, [key.toLowerCase()]);
    expect(() => receipt.recordIds.clear(), throwsUnsupportedError);
    for (final invalid in <Object?>[
      null,
      {...body, 'requestId': createAssetImportRequestId()},
      {...body, 'recordCount': 1.0},
      {...body, 'recordCount': 2},
      {...body, 'recordIds': <String>[]},
      {
        ...body,
        'recordIds': ['invalid'],
      },
      {
        ...body,
        'recordIds': [null],
      },
      {...body, 'extra': true},
    ]) {
      expect(
        () => AssetImportReceipt.parse(invalid, draft),
        throwsFormatException,
      );
    }
  });

  test(
    'confirmation rejects unacknowledged or changed session without sending',
    () async {
      final operation = AssetImportOperation(prepare(), 7);
      final source = PendingImportSource();
      await expectLater(
        operation.confirm(
          source,
          acknowledged: false,
          currentAccountId: owner,
          currentSessionRevision: 7,
        ),
        throwsStateError,
      );
      await expectLater(
        operation.confirm(
          source,
          acknowledged: true,
          currentAccountId: owner,
          currentSessionRevision: 8,
        ),
        throwsStateError,
      );
      expect(source.calls, isEmpty);
    },
  );
  test('concurrent confirmation is blocked and invalidation suppresses late success', () async {
    final operation = AssetImportOperation(prepare(), 7);
    final source = PendingImportSource();
    Future<void> confirm() => operation.confirm(
      source,
      acknowledged: true,
      currentAccountId: owner,
      currentSessionRevision: 7,
    );
    final pending = confirm();
    await expectLater(confirm(), throwsStateError);
    operation.invalidate();
    source.result.complete(
      AssetImportReceipt.parse({
        'requestId': operation.draft.requestId,
        'recordCount': 1,
        'recordIds': [key],
      }, operation.draft),
    );
    await expectLater(pending, throwsStateError);
    expect(operation.receipt, isNull);
    expect(operation.busy, isFalse);
    expect(source.calls.length, 1);
  });
  test('unknown outcome preserves exact draft for explicit replay', () async {
    final operation = AssetImportOperation(prepare(), 7);
    final source = PendingImportSource();
    final pending = operation.confirm(
      source,
      acknowledged: true,
      currentAccountId: owner,
      currentSessionRevision: 7,
    );
    source.result.completeError(StateError('synthetic unknown'));
    await expectLater(pending, throwsStateError);
    final retry = PendingImportSource();
    retry.result.complete(
      AssetImportReceipt.parse({
        'requestId': operation.draft.requestId,
        'recordCount': 1,
        'recordIds': [key],
      }, operation.draft),
    );
    await operation.confirm(
      retry,
      acknowledged: true,
      currentAccountId: owner,
      currentSessionRevision: 7,
    );
    expect(identical(source.calls.single, retry.calls.single), isTrue);
    await expectLater(
      operation.confirm(
        retry,
        acknowledged: true,
        currentAccountId: owner,
        currentSessionRevision: 7,
      ),
      throwsStateError,
    );
    expect(retry.calls.length, 1);
  });
}

class PendingImportSource implements AssetImportSource {
  final calls = <AssetImportDraft>[];
  final result = Completer<AssetImportReceipt>();
  @override
  Future<AssetImportReceipt> importInventory(
    AssetImportDraft draft, {
    required int sessionRevision,
  }) {
    calls.add(draft);
    return result.future;
  }
}

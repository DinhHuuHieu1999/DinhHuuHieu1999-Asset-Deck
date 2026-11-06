import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset_export_v4.dart';
import 'package:asset_desk/api/asset_import_v4.dart';
import 'package:asset_desk/api/asset_import_v4_operation.dart';

import 'asset_export_v4_test.dart' show exportV4Fixture;

class DelayedSource implements AssetImportV4Source {
  final reply = Completer<AssetImportV4Receipt>();
  int calls = 0;
  @override
  Future<AssetImportV4Receipt> importInventoryV4(
    AssetImportV4Draft draft, {
    required int sessionRevision,
  }) {
    calls++;
    return reply.future;
  }
}

void main() {
  const owner = 'aaaaaaaaaaaaaaaaaaaaaaaa';
  Future<AssetImportV4Draft> draft() async => AssetImportV4Draft.prepare(
    snapshot: await AssetExportV4.parse(
      exportV4Fixture(),
      digest: (_) async => 'a' * 64,
    ),
    accountId: owner,
    requestId: '12345678-1234-4123-8123-123456789abc',
  );
  Future<void> confirm(
    AssetImportV4Operation op,
    DelayedSource source, {
    bool acknowledged = true,
    String account = owner,
    int revision = 1,
  }) => op.confirm(
    source,
    acknowledged: acknowledged,
    currentAccountId: account,
    currentSessionRevision: revision,
  );
  test('acknowledgment, account and revision reject before any call', () async {
    final op = AssetImportV4Operation(await draft(), 1);
    final source = DelayedSource();
    await expectLater(
      confirm(op, source, acknowledged: false),
      throwsStateError,
    );
    await expectLater(confirm(op, source, revision: 2), throwsStateError);
    await expectLater(
      confirm(op, source, account: 'bbbbbbbbbbbbbbbbbbbbbbbb'),
      throwsA(anything),
    );
    expect(source.calls, 0);
    expect(op.attempted, isFalse);
  });
  test(
    'single-flight rejects duplicate and invalidation rejects late receipt',
    () async {
      final value = await draft();
      final op = AssetImportV4Operation(value, 1);
      final source = DelayedSource();
      final pending = confirm(op, source);
      expect(op.busy, isTrue);
      await expectLater(confirm(op, source), throwsStateError);
      op.invalidate();
      final rejected = expectLater(pending, throwsStateError);
      source.reply.complete(
        AssetImportV4Receipt.parse({
          'requestId': value.requestId,
          'recordCount': 1,
          'recordIds': ['87654321-4321-4321-8321-123456789abc'],
        }, value),
      );
      await rejected;
      expect(op.receipt, isNull);
      expect(op.busy, isFalse);
      expect(op.attempted, isTrue);
      await expectLater(confirm(op, source), throwsStateError);
      expect(source.calls, 1);
    },
  );
  test(
    'recovered operation starts attempted and preserves exact request',
    () async {
      final value = await draft();
      final op = AssetImportV4Operation.recovered(value, 1);
      expect(op.attempted, isTrue);
      expect(op.draft, same(value));
      expect(op.receipt, isNull);
    },
  );
}

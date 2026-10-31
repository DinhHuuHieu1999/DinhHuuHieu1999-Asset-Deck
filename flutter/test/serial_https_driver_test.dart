import 'package:flutter_test/flutter_test.dart';

import '../lib/api/asset.dart';
import '../lib/api/asset_store.dart';
import '../tool/serial_https_acceptance.dart';
import '../tool/client_https_acceptance.dart' show validateDriverArgs;

class SnapshotStore implements AssetStore {
  final offsets = <int>[];
  bool overflow = false;
  int version = 1;
  @override
  Future<AssetPage> list({
    String sort = 'updated_desc',
    required String query,
    required String status,
    String category = '',
    required int offset,
  }) async {
    offsets.add(offset);
    return AssetPage([
      AssetRecord(
        id: 'row-$offset',
        input: const AssetInput(
          name: 'Synthetic',
          category: 'fixture',
          serial: '%_literal',
          status: 'stored',
        ),
        version: version,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    ], overflow || offset == 0 ? offset + 50 : null);
  }

  @override
  Future<AssetRecord> create(AssetInput input) => throw StateError('No writes');
  @override
  Future<AssetRecord> update(AssetRecord original, AssetInput input) =>
      throw StateError('No writes');
}

void main() {
  test(
    'snapshot reads every page and retains metadata for mutation detection',
    () async {
      final store = SnapshotStore();
      final before = await serialInventorySnapshot(store);
      expect(store.offsets, [0, 50]);
      expect(before, contains('%_literal'));
      store.version = 2;
      expect(await serialInventorySnapshot(store), isNot(before));
    },
  );
  test(
    'unexpected endless continuation fails within the fixture bound',
    () async {
      final store = SnapshotStore()..overflow = true;
      await expectLater(serialInventorySnapshot(store), throwsStateError);
      expect(store.offsets, [0, 50, 100]);
    },
  );
  test(
    'driver rejects non-fixture arguments before any client is constructed',
    () {
      for (final endpoint in [
        'http://localhost:29443/api/v1',
        'https://example.com:29443/api/v1',
        'https://localhost:8443/api/v1',
        'https://localhost:29443/api/v1?token=x',
      ]) {
        expect(
          () => validateDriverArgs(['--synthetic-only', endpoint, 'a' * 32]),
          throwsStateError,
        );
      }
      expect(
        validateDriverArgs([
          '--synthetic-only',
          'https://localhost:29443/api/v1',
          'a' * 32,
        ]).port,
        29443,
      );
    },
  );
}

import 'dart:convert';
import 'dart:math';

import 'asset_export.dart';

/// Immutable, account-bound operation prepared only from a verified snapshot.
/// Keep this exact instance after an unknown outcome; never mint a new key.
class AssetImportDraft {
  AssetImportDraft._(this.accountId, this.requestId, this.records, this.json);

  final String accountId;
  final String requestId;
  final List<Map<String, Object?>> records;
  final String json;
  int get count => records.length;

  /// Discard source identities and metadata; the server owns new identities.
  factory AssetImportDraft.prepare({
    required AssetExport snapshot,
    required String accountId,
    required String requestId,
  }) {
    if (!RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(accountId) ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
        ).hasMatch(requestId)) {
      throw const FormatException('Invalid import operation identity');
    }
    if (snapshot.count < 1 || snapshot.count > 500) {
      throw const FormatException('Import requires 1-500 assets');
    }
    final records = List<Map<String, Object?>>.unmodifiable([
      for (final record in snapshot.records)
        Map<String, Object?>.unmodifiable(record.input.toJson()),
    ]);
    final key = requestId.toLowerCase();
    final json = jsonEncode({'requestId': key, 'records': records});
    if (utf8.encode(json).length > 1024 * 1024) {
      throw const FormatException('Import exceeds 1 MiB');
    }
    return AssetImportDraft._(accountId.toLowerCase(), key, records, json);
  }

  /// Account changes invalidate the operation instead of retargeting its payload.
  void requireAccount(String currentAccountId) {
    if (currentAccountId.toLowerCase() != accountId) {
      throw StateError('Import draft belongs to another account');
    }
  }
}

/// Generate one UUID v4 for a new operation, never for an uncertain retry.
String createAssetImportRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Validate the complete receipt before treating an operation as successful.
class AssetImportReceipt {
  AssetImportReceipt._(this.requestId, this.recordIds);
  final String requestId;
  final List<String> recordIds;

  factory AssetImportReceipt.parse(Object? value, AssetImportDraft draft) {
    if (value is! Map<String, Object?> ||
        value.length != 3 ||
        value['requestId'] != draft.requestId ||
        value['recordCount'] is! int ||
        value['recordCount'] != draft.count ||
        value['recordIds'] is! List) {
      throw const FormatException('Invalid import receipt');
    }
    final ids = value['recordIds']! as List;
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    if (ids.length != draft.count ||
        ids.any((id) => id is! String || !uuid.hasMatch(id))) {
      throw const FormatException('Invalid imported identities');
    }
    final normalized = ids
        .cast<String>()
        .map((id) => id.toLowerCase())
        .toList();
    if (normalized.toSet().length != normalized.length) {
      throw const FormatException('Duplicate imported identities');
    }
    return AssetImportReceipt._(draft.requestId, List.unmodifiable(normalized));
  }
}

/// Explicit mutation capability, separate from inventory and read-only Inspect.
abstract interface class AssetImportSource {
  Future<AssetImportReceipt> importInventory(
    AssetImportDraft draft, {
    required int sessionRevision,
  });
}

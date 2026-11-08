import 'dart:convert';

import 'asset_export_v2.dart';
import 'asset_dates.dart';
import 'asset.dart';
import 'strict_export_json.dart';

/// Immutable, account-bound operation prepared only from a verified snapshot.
/// Keep this exact instance after an unknown outcome; never mint a new key.
class AssetImportV2Draft {
  AssetImportV2Draft._(this.accountId, this.requestId, this.records, this.json);

  final String accountId;
  final String requestId;
  final List<Map<String, Object?>> records;
  final String json;
  int get count => records.length;

  /// Discard source identities and metadata; the server owns new identities.
  factory AssetImportV2Draft.prepare({
    required AssetExportV2 snapshot,
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
        Map<String, Object?>.unmodifiable({
          ...record.asset.input.toJson(),
          'purchasedOn': record.dates.purchasedOn,
          'warrantyExpiresOn': record.dates.warrantyExpiresOn,
        }),
    ]);
    final key = requestId.toLowerCase();
    final json = jsonEncode({'requestId': key, 'records': records});
    if (utf8.encode(json).length > 1024 * 1024) {
      throw const FormatException('Import exceeds 1 MiB');
    }
    return AssetImportV2Draft._(accountId.toLowerCase(), key, records, json);
  }

  /// Restore a validated exact request; never generate a replacement key.
  factory AssetImportV2Draft.restore({
    required String accountId,
    required String requestJson,
  }) {
    if (!RegExp(r'^[0-9a-f]{24}$').hasMatch(accountId)) {
      throw const FormatException('Invalid recovery account');
    }
    final value = decodeAssetExportJson(requestJson);
    if (value is! Map<String, Object?> ||
        value.length != 2 ||
        value['requestId'] is! String ||
        value['records'] is! List) {
      throw const FormatException('Invalid recovery request');
    }
    final key = value['requestId']! as String;
    final rows = value['records']! as List;
    if (!RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(key) ||
        rows.isEmpty ||
        rows.length > 500) {
      throw const FormatException('Invalid recovery operation');
    }
    final records = <Map<String, Object?>>[];
    const baseFields = ['name', 'category', 'serial', 'status', 'notes'];
    const fields = [...baseFields, 'purchasedOn', 'warrantyExpiresOn'];
    for (final row in rows) {
      if (row is! Map<String, Object?> ||
          row.length != fields.length ||
          !fields.every(row.containsKey) ||
          !baseFields.every((field) => row[field] is String) ||
          (row['purchasedOn'] != null && row['purchasedOn'] is! String) ||
          (row['warrantyExpiresOn'] != null &&
              row['warrantyExpiresOn'] is! String)) {
        throw const FormatException('Invalid recovery fields');
      }
      final input = AssetInput(
        name: row['name']! as String,
        category: row['category']! as String,
        serial: row['serial']! as String,
        status: row['status']! as String,
        notes: row['notes']! as String,
      ).toJson();
      if (!baseFields.every((field) => input[field] == row[field])) {
        throw const FormatException(
          'Recovery fields must retain reviewed values',
        );
      }
      final dates = AssetDatesInput(
        purchasedOn: row['purchasedOn'] as String?,
        warrantyExpiresOn: row['warrantyExpiresOn'] as String?,
      );
      dates.validate();
      records.add(
        Map<String, Object?>.unmodifiable({
          ...input,
          'purchasedOn': dates.purchasedOn,
          'warrantyExpiresOn': dates.warrantyExpiresOn,
        }),
      );
    }
    return AssetImportV2Draft._(
      accountId,
      key,
      List.unmodifiable(records),
      requestJson,
    );
  }

  /// Account changes invalidate the operation instead of retargeting its payload.
  void requireAccount(String currentAccountId) {
    if (currentAccountId.toLowerCase() != accountId) {
      throw StateError('Import draft belongs to another account');
    }
  }
}

/// Validate the complete receipt before treating an operation as successful.
class AssetImportV2Receipt {
  AssetImportV2Receipt._(this.requestId, this.recordIds);
  final String requestId;
  final List<String> recordIds;

  factory AssetImportV2Receipt.parse(Object? value, AssetImportV2Draft draft) {
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
    return AssetImportV2Receipt._(
      draft.requestId,
      List.unmodifiable(normalized),
    );
  }
}

/// Explicit mutation capability, separate from inventory and read-only Inspect.
abstract interface class AssetImportV2Source {
  Future<AssetImportV2Receipt> importInventoryV2(
    AssetImportV2Draft draft, {
    required int sessionRevision,
  });
}

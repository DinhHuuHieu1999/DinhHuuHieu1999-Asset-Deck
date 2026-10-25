import 'dart:convert';
import 'dart:typed_data';

import 'asset.dart';
import 'strict_export_json.dart';

/// Native digest callback; callers must use an actual SHA-256 implementation.
typedef AssetExportDigest = Future<String> Function(Uint8List bytes);

/// Separate capability so inventory-only stores are not forced to expose exports.
abstract interface class AssetExportSource {
  Future<AssetExport> exportInventory({required AssetExportDigest digest});
}

/// Complete validated inventory; construct only after exact-byte digest verification.
class AssetExport {
  AssetExport._(this.json, this.exportedAt, List<AssetRecord> records)
    : records = List.unmodifiable(records);
  final String json;
  final DateTime exportedAt;
  final List<AssetRecord> records;
  int get count => records.length;

  /// Reject unsupported, incomplete, oversized or inconsistent snapshots before saving.
  static Future<AssetExport> parse(
    Map<String, Object?> envelope, {
    required AssetExportDigest digest,
  }) async {
    if (envelope.length != 4 ||
        envelope['format'] != 'asset-desk-inventory' ||
        envelope['schemaVersion'] is! int ||
        envelope['schemaVersion'] != 1 ||
        envelope['payload'] is! String ||
        envelope['sha256'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(envelope['sha256']! as String)) {
      throw const FormatException('Unsupported inventory export envelope');
    }
    final serialized = jsonEncode(envelope);
    if (utf8.encode(serialized).length > 1024 * 1024) {
      throw const FormatException('Inventory export exceeds 1 MiB');
    }
    final payload = envelope['payload']! as String;
    final decoded = decodeAssetExportJson(payload);
    if (decoded is! Map<String, Object?> ||
        decoded.length != 4 ||
        decoded['complete'] != true ||
        decoded['recordCount'] is! int ||
        decoded['records'] is! List ||
        decoded['exportedAt'] is! String) {
      throw const FormatException('Invalid inventory snapshot');
    }
    final exportedAt = DateTime.tryParse(decoded['exportedAt']! as String);
    if (exportedAt == null || !exportedAt.isUtc) {
      throw const FormatException('Invalid inventory snapshot time');
    }
    final rows = decoded['records']! as List;
    if (rows.length > 500 || decoded['recordCount'] != rows.length) {
      throw const FormatException('Incomplete inventory export');
    }
    final records = <AssetRecord>[];
    final ids = <String>{};
    for (final row in rows) {
      if (row is! Map<String, Object?> || row.length != 9) {
        throw const FormatException('Invalid inventory export record');
      }
      final record = AssetRecord.fromJson(row);
      if (!ids.add(record.id.toLowerCase())) {
        throw const FormatException('Duplicate inventory identity');
      }
      records.add(record);
    }
    final actual = await digest(Uint8List.fromList(utf8.encode(payload)));
    if (actual != envelope['sha256']) {
      throw const FormatException('Inventory checksum mismatch');
    }
    return AssetExport._(serialized, exportedAt, records);
  }
}

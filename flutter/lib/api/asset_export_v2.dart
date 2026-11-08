import 'dart:convert';
import 'dart:typed_data';

import 'asset.dart';
import 'asset_dates.dart';
import 'asset_export.dart';
import 'strict_export_json.dart';

/// Separate capability; v1 export/import contracts remain unchanged.
abstract interface class AssetExportV2Source {
  Future<AssetExportV2> exportInventoryV2({required AssetExportDigest digest});
}

/// One immutable base record and date pair from the same server snapshot.
class AssetExportV2Record {
  const AssetExportV2Record({required this.asset, required this.dates});
  final AssetRecord asset;
  final AssetDatesInput dates;
}

/// Date-aware export; only exact-byte checksum verification constructs snapshots.
class AssetExportV2 {
  AssetExportV2._(this.json, this.exportedAt, List<AssetExportV2Record> records)
    : records = List.unmodifiable(records);
  final String json;
  final DateTime exportedAt;
  final List<AssetExportV2Record> records;
  int get count => records.length;

  /// Refuse unsupported schemas, missing dates, partial data and checksum mismatch.
  static Future<AssetExportV2> parse(
    Map<String, Object?> envelope, {
    required AssetExportDigest digest,
  }) async {
    if (envelope.length != 4 ||
        envelope['format'] != 'asset-desk-inventory' ||
        envelope['schemaVersion'] is! int ||
        envelope['schemaVersion'] != 2 ||
        envelope['payload'] is! String ||
        envelope['sha256'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(envelope['sha256']! as String)) {
      throw const FormatException('Unsupported inventory v2 envelope');
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
      throw const FormatException('Invalid inventory v2 snapshot');
    }
    final exportedAt = DateTime.tryParse(decoded['exportedAt']! as String);
    if (exportedAt == null || !exportedAt.isUtc) {
      throw const FormatException('Invalid inventory snapshot time');
    }
    final rows = decoded['records']! as List;
    if (rows.length > 500 || decoded['recordCount'] != rows.length) {
      throw const FormatException('Incomplete inventory export');
    }
    const fields = {
      'id',
      'name',
      'category',
      'serial',
      'status',
      'notes',
      'version',
      'createdAt',
      'updatedAt',
      'purchasedOn',
      'warrantyExpiresOn',
    };
    final records = <AssetExportV2Record>[];
    final ids = <String>{};
    for (final row in rows) {
      if (row is! Map<String, Object?> ||
          row.length != fields.length ||
          !fields.every(row.containsKey)) {
        throw const FormatException('Invalid inventory v2 record');
      }
      final asset = AssetRecord.fromJson(row);
      final dates = AssetDates.fromJson({
        'id': row['id'],
        'version': row['version'],
        'purchasedOn': row['purchasedOn'],
        'warrantyExpiresOn': row['warrantyExpiresOn'],
      });
      if (!ids.add(asset.id.toLowerCase())) {
        throw const FormatException('Duplicate inventory identity');
      }
      records.add(AssetExportV2Record(asset: asset, dates: dates.input));
    }
    final actual = await digest(Uint8List.fromList(utf8.encode(payload)));
    if (actual != envelope['sha256']) {
      throw const FormatException('Inventory checksum mismatch');
    }
    return AssetExportV2._(serialized, exportedAt, records);
  }
}

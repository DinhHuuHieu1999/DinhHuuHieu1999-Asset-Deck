import 'dart:convert';
import 'dart:typed_data';

import 'asset.dart';
import 'asset_dates.dart';
import 'asset_export.dart';
import 'asset_export_v3.dart';
import 'strict_export_json.dart';

/// Separate capability; v1/v2 export and import contracts remain unchanged.
abstract interface class AssetExportV4Source {
  Future<AssetExportV4> exportInventoryV4({required AssetExportDigest digest});
}

/// One immutable base record and date pair from the same server snapshot.
class AssetExportV4Record {
  const AssetExportV4Record({
    required this.asset,
    required this.dates,
    required this.location,
    required this.lastCheckedDate,
  });
  final AssetRecord asset;
  final AssetDatesInput dates;
  final String? location;
  final String? lastCheckedDate;
}

/// Location-aware export; only exact-byte checksum verification constructs snapshots.
class AssetExportV4 {
  AssetExportV4._(this.json, this.exportedAt, List<AssetExportV4Record> records)
    : records = List.unmodifiable(records);
  final String json;
  final DateTime exportedAt;
  final List<AssetExportV4Record> records;
  int get count => records.length;

  /// Refuse unsupported schemas, missing dates, partial data and checksum mismatch.
  static Future<AssetExportV4> parse(
    Map<String, Object?> envelope, {
    required AssetExportDigest digest,
  }) async {
    if (envelope.length != 4 ||
        envelope['format'] != 'asset-desk-inventory' ||
        envelope['schemaVersion'] is! int ||
        envelope['schemaVersion'] != 4 ||
        envelope['payload'] is! String ||
        envelope['sha256'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(envelope['sha256']! as String)) {
      throw const FormatException('Unsupported inventory v4 envelope');
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
      throw const FormatException('Invalid inventory v4 snapshot');
    }
    final exportedAt = DateTime.tryParse(decoded['exportedAt']! as String);
    if (exportedAt == null || !exportedAt.isUtc) {
      throw const FormatException('Invalid inventory snapshot time');
    }
    final rows = decoded['records']! as List;
    if (rows.length > 500 || decoded['recordCount'] != rows.length) {
      throw const FormatException('Incomplete inventory export');
    }
    final records = parseAssetExportV4Records(rows);
    final actual = await digest(Uint8List.fromList(utf8.encode(payload)));
    if (actual != envelope['sha256']) {
      throw const FormatException('Inventory checksum mismatch');
    }
    return AssetExportV4._(serialized, exportedAt, records);
  }
}

/// Validate exact public v4 records without weakening the existing v3 parser.
List<AssetExportV4Record> parseAssetExportV4Records(List<Object?> rows) {
  final projected = <Map<String, Object?>>[];
  final dates = <String?>[];
  for (final row in rows) {
    if (row is! Map<String, Object?> || !row.containsKey('lastCheckedDate'))
      throw const FormatException('Missing inventory check date');
    final date = row['lastCheckedDate'];
    if (date != null && !isAssetCalendarDate(date))
      throw const FormatException('Invalid inventory check date');
    projected.add({...row}..remove('lastCheckedDate'));
    dates.add(date as String?);
  }
  final base = parseAssetExportV3Records(projected);
  return List.unmodifiable([
    for (var i = 0; i < base.length; i++)
      AssetExportV4Record(
        asset: base[i].asset,
        dates: base[i].dates,
        location: base[i].location,
        lastCheckedDate: dates[i],
      ),
  ]);
}

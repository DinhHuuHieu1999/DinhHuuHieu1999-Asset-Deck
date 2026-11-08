import 'dart:convert';
import 'dart:typed_data';

import 'asset.dart';
import 'asset_export.dart';
import 'asset_export_v3.dart';
import 'asset_location.dart';
import 'asset_sort.dart';
import 'asset_warranty.dart';
import 'strict_export_json.dart';

/// Explicit immutable selection identity, not a full-inventory backup scope.
class AssetSelectionScope {
  AssetSelectionScope._(this.filters);
  final Map<String, Object?> filters;

  /// Encode only validated, applied filters; no paging or owner is accepted.
  Map<String, String> toQuery() {
    final result = <String, String>{
      for (final key in ['q', 'status', 'category', 'locationMode', 'sort'])
        key: filters[key]! as String,
      if (filters['locationMode'] == 'exact')
        'location': filters['location']! as String,
    };
    final window = filters['warranty'] as Map<String, Object?>?;
    if (window != null) {
      result['warranty'] = window['filter']! as String;
      result['asOf'] = window['asOf']! as String;
    }
    return result;
  }

  factory AssetSelectionScope.fromJson(Map<String, Object?> value) {
    const keys = {
      'q',
      'status',
      'category',
      'locationMode',
      'location',
      'sort',
      'warranty',
    };
    if (value.length != keys.length || !keys.every(value.containsKey)) {
      throw const FormatException('Invalid selection filters');
    }
    for (final entry in {'q': 120, 'category': 64}.entries) {
      final text = value[entry.key];
      if (text is! String ||
          text != text.trim() ||
          text.length > entry.value ||
          text.contains('\u0000')) {
        throw const FormatException('Invalid selection text');
      }
    }
    if (!['', ...assetStatuses].contains(value['status']) ||
        !assetSorts.contains(value['sort']) ||
        !['all', 'unknown', 'exact'].contains(value['locationMode'])) {
      throw const FormatException('Invalid selection filters');
    }
    final location = value['location'];
    if (value['locationMode'] == 'exact'
        ? location == null || normalizeAssetLocation(location) != location
        : location != null) {
      throw const FormatException('Invalid selection location');
    }
    final warranty = value['warranty'];
    Map<String, Object?>? window;
    if (warranty != null) {
      if (warranty is! Map<String, Object?> ||
          warranty.length != 3 ||
          !assetWarrantyFilters.contains(warranty['filter']) ||
          warranty['asOf'] is! String ||
          warranty['through'] !=
              assetWarrantyThrough(warranty['asOf']! as String)) {
        throw const FormatException('Invalid selection warranty');
      }
      window = Map.unmodifiable(warranty);
    }
    return AssetSelectionScope._(
      Map.unmodifiable({...value, 'warranty': window}),
    );
  }
}

/// Verified selection file; never accepted by the full inventory import parsers.
class AssetSelectionExport {
  AssetSelectionExport._(this.json, this.exportedAt, this.scope, this.records);
  final String json;
  final DateTime exportedAt;
  final AssetSelectionScope scope;
  final List<AssetExportV3Record> records;
  int get count => records.length;

  /// Verify exact payload bytes, scope metadata and public records before use.
  static Future<AssetSelectionExport> parse(
    Map<String, Object?> envelope, {
    required AssetExportDigest digest,
  }) async {
    if (envelope.length != 4 ||
        envelope['format'] != 'asset-desk-inventory-selection' ||
        envelope['schemaVersion'] is! int ||
        envelope['schemaVersion'] != 1 ||
        envelope['payload'] is! String ||
        envelope['sha256'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(envelope['sha256']! as String)) {
      throw const FormatException('Unsupported selection envelope');
    }
    final serialized = jsonEncode(envelope);
    if (utf8.encode(serialized).length > 1024 * 1024)
      throw const FormatException('Selection exceeds 1 MiB');
    final payload = envelope['payload']! as String;
    final decoded = decodeAssetExportJson(payload);
    const fields = {
      'exportedAt',
      'scope',
      'allMatchesIncluded',
      'filters',
      'recordCount',
      'records',
    };
    if (decoded is! Map<String, Object?> ||
        decoded.length != fields.length ||
        !fields.every(decoded.containsKey) ||
        decoded['scope'] != 'filtered-selection' ||
        decoded['allMatchesIncluded'] != true ||
        decoded['filters'] is! Map<String, Object?> ||
        decoded['recordCount'] is! int ||
        decoded['records'] is! List ||
        decoded['exportedAt'] is! String) {
      throw const FormatException('Invalid selection snapshot');
    }
    final time = DateTime.tryParse(decoded['exportedAt']! as String);
    if (time == null || !time.isUtc)
      throw const FormatException('Invalid selection time');
    final rows = decoded['records']! as List;
    if (rows.length > 500 || decoded['recordCount'] != rows.length)
      throw const FormatException('Incomplete selection');
    final scope = AssetSelectionScope.fromJson(
      decoded['filters']! as Map<String, Object?>,
    );
    final records = parseAssetExportV3Records(rows);
    if (await digest(Uint8List.fromList(utf8.encode(payload))) !=
        envelope['sha256']) {
      throw const FormatException('Selection checksum mismatch');
    }
    return AssetSelectionExport._(serialized, time, scope, records);
  }
}

/// Separate capability leaves existing inventory stores and full export unchanged.
abstract interface class AssetSelectionExportSource {
  Future<AssetSelectionExport> exportSelection({
    required AssetSelectionScope scope,
    required AssetExportDigest digest,
  });
}

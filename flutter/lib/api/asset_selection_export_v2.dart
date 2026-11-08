import 'dart:convert';
import 'dart:typed_data';

import 'asset_dates.dart';
import 'asset_export.dart';
import 'asset_export_v3.dart';
import 'asset_selection_export.dart';
import 'strict_export_json.dart';

/// Explicit immutable v2 filter identity with a tagged manual check predicate.
class AssetSelectionScopeV2 {
  AssetSelectionScopeV2._(this.base, this.check);
  final AssetSelectionScope base;
  final Map<String, Object?> check;
  factory AssetSelectionScopeV2.fromJson(Map<String, Object?> value) {
    final rest = {...value};
    final check = rest.remove('check');
    if (check is! Map<String, Object?>)
      throw const FormatException('Invalid selection check');
    final mode = check['mode'];
    final noCutoff = mode == 'all' || mode == 'unknown';
    final dated = mode == 'before' || mode == 'on_or_after';
    if (!(noCutoff && check.length == 1 ||
        dated && check.length == 2 && isAssetCalendarDate(check['cutoff'])))
      throw const FormatException('Invalid selection check');
    return AssetSelectionScopeV2._(
      AssetSelectionScope.fromJson(rest),
      Map.unmodifiable(check),
    );
  }

  /// Encode only explicit applied predicates, never owner or pagination fields.
  Map<String, String> toQuery() => {
    ...base.toQuery(),
    'checkMode': check['mode']! as String,
    if (check.containsKey('cutoff')) 'checkCutoff': check['cutoff']! as String,
  };
}

/// One base snapshot record with its manual check date from the same snapshot.
class AssetSelectionV2Record {
  const AssetSelectionV2Record(this.record, this.lastCheckedDate);
  final AssetExportV3Record record;
  final String? lastCheckedDate;
}

/// Verified selection file; never accepted by the full inventory import parsers.
class AssetSelectionExportV2 {
  AssetSelectionExportV2._(
    this.json,
    this.exportedAt,
    this.scope,
    this.records,
  );
  final String json;
  final DateTime exportedAt;
  final AssetSelectionScopeV2 scope;
  final List<AssetSelectionV2Record> records;
  int get count => records.length;

  /// Verify exact payload bytes, scope metadata and public records before use.
  static Future<AssetSelectionExportV2> parse(
    Map<String, Object?> envelope, {
    required AssetExportDigest digest,
  }) async {
    if (envelope.length != 4 ||
        envelope['format'] != 'asset-desk-inventory-selection' ||
        envelope['schemaVersion'] is! int ||
        envelope['schemaVersion'] != 2 ||
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
    final scope = AssetSelectionScopeV2.fromJson(
      decoded['filters']! as Map<String, Object?>,
    );
    final projected = <Map<String, Object?>>[];
    final dates = <String?>[];
    for (final row in rows) {
      if (row is! Map<String, Object?> || !row.containsKey('lastCheckedDate'))
        throw const FormatException('Missing selection check date');
      final date = row['lastCheckedDate'];
      if (date != null && !isAssetCalendarDate(date))
        throw const FormatException('Invalid selection check date');
      final mode = scope.check['mode'];
      final cutoff = scope.check['cutoff'] as String?;
      if ((mode == 'unknown' && date != null) ||
          (mode == 'before' &&
              (date == null || (date as String).compareTo(cutoff!) >= 0)) ||
          (mode == 'on_or_after' &&
              (date == null || (date as String).compareTo(cutoff!) < 0)))
        throw const FormatException('Selection check scope mismatch');
      projected.add({...row}..remove('lastCheckedDate'));
      dates.add(date as String?);
    }
    final baseRecords = parseAssetExportV3Records(projected);
    final records = List<AssetSelectionV2Record>.unmodifiable([
      for (var i = 0; i < baseRecords.length; i++)
        AssetSelectionV2Record(baseRecords[i], dates[i]),
    ]);
    if (await digest(Uint8List.fromList(utf8.encode(payload))) !=
        envelope['sha256']) {
      throw const FormatException('Selection checksum mismatch');
    }
    return AssetSelectionExportV2._(serialized, time, scope, records);
  }
}

/// Separate capability leaves existing inventory stores and full export unchanged.
abstract interface class AssetSelectionExportV2Source {
  Future<AssetSelectionExportV2> exportSelectionV2({
    required AssetSelectionScopeV2 scope,
    required AssetExportDigest digest,
  });
}

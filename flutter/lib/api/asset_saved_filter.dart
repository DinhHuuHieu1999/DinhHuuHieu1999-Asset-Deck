import 'asset_dates.dart';

/// Immutable schema-v1 query; fixed dates and literal predicates stay unchanged.
class AssetSavedFilterQuery {
  AssetSavedFilterQuery._(this.values);
  final Map<String, String> values;
  static const fields = {
    'q',
    'status',
    'category',
    'sort',
    'locationMode',
    'location',
    'warranty',
    'asOf',
    'checkMode',
    'checkBefore',
    'checkOnOrAfter',
  };
  factory AssetSavedFilterQuery.fromJson(Map<String, Object?> json) {
    if (json.length != fields.length || !fields.every((k) => json[k] is String))
      throw const FormatException('Invalid saved query');
    final v = json.map((k, v) => MapEntry(k, v! as String));
    final enums = {
      'status': ['', 'in_use', 'stored', 'repair', 'retired'],
      'sort': ['updated_desc', 'name_asc', 'checked_asc'],
      'locationMode': ['all', 'exact', 'unknown'],
      'warranty': ['all', 'expired', 'expiring_soon'],
      'checkMode': ['all', 'unchecked', 'before', 'on_or_after'],
    };
    if (enums.entries.any((e) => !e.value.contains(v[e.key])) ||
        v['q']!.length > 120 ||
        v['category']!.length > 64 ||
        v.values.any(
          (s) =>
              RegExp(r'[\x00-\x1f\x7f]').hasMatch(s) ||
              s.runes.any((r) => r >= 0xd800 && r <= 0xdfff),
        ))
      throw const FormatException('Invalid saved query');
    if (v['locationMode'] == 'exact'
        ? v['location']!.isEmpty ||
              v['location']!.length > 120 ||
              v['location']!.trim() != v['location']
        : v['location'] != '')
      throw const FormatException('Invalid saved location');
    if (v['warranty'] == 'all'
        ? v['asOf'] != ''
        : !isAssetCalendarDate(v['asOf']))
      throw const FormatException('Invalid fixed reference');
    for (final e in {
      'before': 'checkBefore',
      'on_or_after': 'checkOnOrAfter',
    }.entries) {
      if (v['checkMode'] == e.key
          ? !isAssetCalendarDate(v[e.value])
          : v[e.value] != '')
        throw const FormatException('Invalid fixed cutoff');
    }
    return AssetSavedFilterQuery._(Map.unmodifiable(v));
  }

  /// Refuse disabled capabilities rather than silently removing predicates.
  void requireCapabilities({
    required bool location,
    required bool warranty,
    required bool check,
    bool checkBefore = true,
    bool checkOnOrAfter = true,
  }) {
    if ((values['checkMode'] == 'before' && !checkBefore) ||
        (values['checkMode'] == 'on_or_after' && !checkOnOrAfter) ||
        (values['locationMode'] != 'all' && !location) ||
        (values['warranty'] != 'all' && !warranty) ||
        ((values['checkMode'] != 'all' || values['sort'] == 'checked_asc') &&
            !check))
      throw const FormatException(
        'Saved filter requires unavailable capabilities',
      );
  }
}

/// Server-owned saved definition, never an inventory snapshot.
class AssetSavedFilter {
  AssetSavedFilter._(this.id, this.name, this.version, this.query);
  final String id, name;
  final int version;
  final AssetSavedFilterQuery query;
  factory AssetSavedFilter.fromJson(Map<String, Object?> json) {
    final id = json['id'], name = json['name'], version = json['version'];
    if (json.length != 5 ||
        json['schemaVersion'] is! int ||
        json['schemaVersion'] != 1 ||
        id is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(id) ||
        version is! int ||
        version < 1 ||
        version > 2147483647 ||
        json['query'] is! Map<String, Object?>)
      throw const FormatException('Invalid saved filter');
    validateSavedFilterName(name);
    if (name != (name as String).trim())
      throw const FormatException('Invalid saved filter name');
    return AssetSavedFilter._(
      id,
      name,
      version,
      AssetSavedFilterQuery.fromJson(json['query']! as Map<String, Object?>),
    );
  }
}

/// Bound user labels without allowing controls or invalid Unicode.
String validateSavedFilterName(Object? value) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.trim().length > 60 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value) ||
      value.runes.any((r) => r >= 0xd800 && r <= 0xdfff))
    throw const FormatException('Invalid saved filter name');
  return value.trim();
}

/// Optional account-owned definition storage; no device preference persistence.
abstract interface class AssetSavedFilterSource {
  Future<List<AssetSavedFilter>> listSavedFilters();
  Future<AssetSavedFilter> createSavedFilter(
    String name,
    AssetSavedFilterQuery query,
  );
  Future<AssetSavedFilter> updateSavedFilter(
    AssetSavedFilter original,
    String name,
    AssetSavedFilterQuery query,
  );
  Future<void> deleteSavedFilter(AssetSavedFilter original);
}

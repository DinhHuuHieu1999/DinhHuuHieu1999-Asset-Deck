import 'asset_location.dart';

/// Optional complete owner counts, independent of list pagination and filters.
abstract interface class AssetLocationOverviewSource {
  Future<AssetLocationOverview> locationOverview();
}

/// Validated immutable snapshot; null locations are represented by unknown count.
class AssetLocationOverview {
  const AssetLocationOverview._(this.total, this.unknown, this.locations);
  final int total;
  final int unknown;
  final List<AssetLocationCount> locations;

  factory AssetLocationOverview.fromJson(Map<String, Object?> json) {
    const fields = {'complete', 'total', 'unknown', 'locations'};
    if (json.length != fields.length ||
        !fields.every(json.containsKey) ||
        json['complete'] != true) {
      throw const FormatException('Invalid location overview');
    }
    const max = 9007199254740991;
    int count(Object? value, {bool positive = false}) {
      if (value is! int || value < (positive ? 1 : 0) || value > max) {
        throw const FormatException('Invalid location count');
      }
      return value;
    }

    final total = count(json['total']);
    final unknown = count(json['unknown']);
    final rows = json['locations'];
    if (rows is! List || rows.length > 1000) {
      throw const FormatException('Invalid location groups');
    }
    var sum = unknown;
    final seen = <String>{};
    final groups = <AssetLocationCount>[];
    for (final row in rows) {
      if (row is! Map ||
          row.length != 2 ||
          !row.containsKey('location') ||
          !row.containsKey('count')) {
        throw const FormatException('Invalid location group');
      }
      final label = normalizeAssetLocation(row['location']);
      if (label == null || label != row['location'] || !seen.add(label)) {
        throw const FormatException('Invalid location label');
      }
      final n = count(row['count'], positive: true);
      sum += n;
      if (sum > max) throw const FormatException('Location count overflow');
      groups.add(AssetLocationCount._(label, n));
    }
    if (sum != total)
      throw const FormatException('Inconsistent location counts');
    return AssetLocationOverview._(total, unknown, List.unmodifiable(groups));
  }
}

/// One exact manual label and its positive owner-scoped asset count.
class AssetLocationCount {
  const AssetLocationCount._(this.location, this.count);
  final String location;
  final int count;
}

import 'asset.dart';

/// Separate read-only capability; list-only stores need not implement overview.
abstract interface class AssetOverviewSource {
  Future<AssetOverview> overview();
}

/// One explicit dimension selected from the full-inventory overview.
class InventoryOverviewSelection {
  const InventoryOverviewSelection._(this.status, this.category);
  final String status, category;

  /// Select a known status, clearing every other inventory filter.
  factory InventoryOverviewSelection.status(String value) {
    if (!assetStatuses.contains(value)) {
      throw const FormatException('Invalid overview status selection');
    }
    return InventoryOverviewSelection._(value, '');
  }

  /// Select an exact label supported by the existing category filter.
  factory InventoryOverviewSelection.category(String value) {
    if (value.isEmpty ||
        value.trim() != value ||
        value.runes.length > 64 ||
        value.contains('\u0000')) {
      throw const FormatException('Invalid overview category selection');
    }
    return InventoryOverviewSelection._('', value);
  }
}

/// Validated immutable complete inventory counts, never inferred from a list page.
class AssetOverview {
  AssetOverview._(
    this.total,
    Map<String, int> statuses,
    Map<String, int> categories,
  ) : byStatus = Map.unmodifiable(statuses),
      byCategory = Map.unmodifiable(categories);

  final int total;
  final Map<String, int> byStatus, byCategory;

  factory AssetOverview.fromJson(Map<String, Object?> json) {
    const maxCount = 9007199254740991;
    int count(Object? value, {bool positive = false}) {
      if (value is! int || value < (positive ? 1 : 0) || value > maxCount) {
        throw const FormatException('Invalid overview count');
      }
      return value;
    }

    if (json['complete'] != true) {
      throw const FormatException('Incomplete inventory overview');
    }
    final total = count(json['total']);
    final rawStatuses = json['byStatus'];
    final rawCategories = json['byCategory'];
    if (rawStatuses is! Map<String, Object?> ||
        rawStatuses.length != assetStatuses.length ||
        !assetStatuses.every(rawStatuses.containsKey) ||
        rawCategories is! List ||
        rawCategories.length > 200) {
      throw const FormatException('Invalid overview groups');
    }
    final statuses = <String, int>{};
    var statusTotal = 0;
    for (final status in assetStatuses) {
      statuses[status] = count(rawStatuses[status]);
      statusTotal += statuses[status]!;
      if (statusTotal > maxCount)
        throw const FormatException('Overview overflow');
    }
    final categories = <String, int>{};
    var categoryTotal = 0;
    for (final raw in rawCategories) {
      if (raw is! Map<String, Object?>) {
        throw const FormatException('Invalid overview category');
      }
      final label = raw['category'];
      if (label is! String ||
          label.trim().isEmpty ||
          label.runes.length > 64 ||
          label.contains('\u0000') ||
          categories.containsKey(label)) {
        throw const FormatException('Invalid overview category');
      }
      final value = count(raw['count'], positive: true);
      categories[label] = value;
      categoryTotal += value;
      if (categoryTotal > maxCount)
        throw const FormatException('Overview overflow');
    }
    if (statusTotal != total || categoryTotal != total) {
      throw const FormatException('Inconsistent inventory overview');
    }
    final sorted = categories.keys.toList()..sort();
    return AssetOverview._(total, statuses, {
      for (final key in sorted) key: categories[key]!,
    });
  }
}

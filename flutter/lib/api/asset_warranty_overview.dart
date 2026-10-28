import 'asset_dates.dart';
import 'asset_warranty.dart';

/// Optional complete counts; list-only and legacy overview sources are unchanged.
abstract interface class AssetWarrantyOverviewSource {
  Future<AssetWarrantyOverview> warrantyOverview({String asOf = ''});
}

/// Validated supported list bucket pinned to the overview calendar reference.
class WarrantyOverviewSelection {
  WarrantyOverviewSelection({required this.warranty, required this.asOf}) {
    if (!assetWarrantyFilters.contains(warranty) ||
        !isAssetCalendarDate(asOf)) {
      throw const FormatException('Invalid warranty overview selection');
    }
  }

  final String warranty, asOf;
}

/// Complete owner counts at one calendar reference, never summed from list pages.
class AssetWarrantyOverview {
  const AssetWarrantyOverview._(
    this.asOf,
    this.through,
    this.total,
    this.expired,
    this.expiringSoon,
    this.later,
    this.unknown,
  );
  final String asOf, through;
  final int total, expired, expiringSoon, later, unknown;

  factory AssetWarrantyOverview.fromJson(
    Map<String, Object?> json, {
    String asOf = '',
  }) {
    const fields = {
      'complete',
      'asOf',
      'through',
      'total',
      'expired',
      'expiringSoon',
      'later',
      'unknown',
    };
    final day = json['asOf'];
    if (json.length != fields.length ||
        !fields.every(json.containsKey) ||
        json['complete'] != true ||
        !isAssetCalendarDate(day) ||
        (asOf.isNotEmpty && day != asOf) ||
        json['through'] != assetWarrantyThrough(day as String)) {
      throw const FormatException('Invalid warranty overview reference');
    }
    const maxCount = 9007199254740991;
    int count(String field) {
      final value = json[field];
      if (value is! int || value < 0 || value > maxCount) {
        throw const FormatException('Invalid warranty overview count');
      }
      return value;
    }

    final total = count('total'),
        expired = count('expired'),
        upcoming = count('expiringSoon'),
        later = count('later'),
        unknown = count('unknown');
    final sum = expired + upcoming + later + unknown;
    if (sum > maxCount || sum != total) {
      throw const FormatException('Inconsistent warranty overview counts');
    }
    return AssetWarrantyOverview._(
      day,
      json['through']! as String,
      total,
      expired,
      upcoming,
      later,
      unknown,
    );
  }
}

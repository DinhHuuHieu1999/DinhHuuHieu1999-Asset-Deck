import 'asset_dates.dart';

/// Optional complete owner counts, independent of paginated inventory filters.
abstract interface class AssetCheckOverviewSource {
  Future<AssetCheckOverview> checkOverview({required String cutoff});
}

/// Strict partition of manual check dates at an explicit calendar boundary.
class AssetCheckOverview {
  const AssetCheckOverview._(
    this.cutoff,
    this.total,
    this.unknown,
    this.before,
    this.onOrAfter,
  );
  final String cutoff;
  final int total, unknown, before, onOrAfter;

  factory AssetCheckOverview.fromJson(
    Map<String, Object?> json, {
    required String cutoff,
  }) {
    const fields = {
      'complete',
      'cutoff',
      'total',
      'unknown',
      'before',
      'onOrAfter',
    };
    if (!isAssetCalendarDate(cutoff) ||
        json.length != fields.length ||
        !fields.every(json.containsKey) ||
        json['complete'] != true ||
        json['cutoff'] != cutoff) {
      throw const FormatException('Invalid check overview reference');
    }
    const max = 9007199254740991;
    int count(String field) {
      final value = json[field];
      if (value is! int || value < 0 || value > max)
        throw const FormatException('Invalid check overview count');
      return value;
    }

    final total = count('total'),
        unknown = count('unknown'),
        before = count('before'),
        onOrAfter = count('onOrAfter');
    final sum = unknown + before + onOrAfter;
    if (sum > max || sum != total)
      throw const FormatException('Inconsistent check overview counts');
    return AssetCheckOverview._(cutoff, total, unknown, before, onOrAfter);
  }
}

/// Explicit overview bucket; its cutoff stays pinned during list navigation.
class CheckOverviewSelection {
  CheckOverviewSelection({required this.mode, required this.cutoff}) {
    if (!const {'unchecked', 'before', 'on_or_after'}.contains(mode) ||
        !isAssetCalendarDate(cutoff)) {
      throw const FormatException('Invalid check overview selection');
    }
  }
  final String mode, cutoff;
}

import 'asset.dart';
import 'asset_warranty.dart';
import 'asset_dates.dart';

/// Optional manual-check capability; unrelated stores retain their existing API.
abstract interface class AssetCheckSource {
  Future<AssetCheckPage> listUnchecked({
    required String query,
    required String status,
    required int offset,
    String sort = 'updated_desc',
    String category = '',
    bool includeLocation = false,
    String locationMode = 'all',
    String? location,
    String warranty = '',
    String asOf = '',
  });
  Future<AssetCheck> readCheckDate(String id);
  Future<AssetCheck> updateCheckDate(AssetCheck original, String? date);
}

/// Manual assertion using the shared asset version, not automatic inspection proof.
class AssetCheck {
  const AssetCheck({
    required this.id,
    required this.version,
    required this.lastCheckedOn,
  });
  final String id;
  final int version;
  final String? lastCheckedOn;

  /// Strict separate endpoint response; never coerce malformed dates or identities.
  factory AssetCheck.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final version = json['version'];
    final date = json['lastCheckedOn'];
    if (json.length != 3 ||
        !json.containsKey('lastCheckedOn') ||
        id is! String ||
        !RegExp(
          r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
        ).hasMatch(id) ||
        version is! int ||
        version < 1 ||
        version > 2147483647 ||
        (date != null && !isAssetCalendarDate(date))) {
      throw const FormatException('Invalid asset check date response');
    }
    return AssetCheck(id: id, version: version, lastCheckedOn: date as String?);
  }

  /// Explicit replacement; the server is authoritative for its UTC day boundary.
  Map<String, Object?> replacement(String? date) {
    if (version < 1 ||
        version > 2147483646 ||
        (date != null && !isAssetCalendarDate(date))) {
      throw const FormatException('Invalid asset check date or version');
    }
    return {'version': version, 'lastCheckedOn': date};
  }
}

/// Validated page preserving optional location and warranty context.
class AssetCheckPage {
  AssetCheckPage(
    this.page, {
    Map<String, String?> locations = const {},
    this.warranty,
  }) : locations = Map.unmodifiable(locations);
  final AssetPage page;
  final Map<String, String?> locations;
  final AssetWarrantyPage? warranty;
}

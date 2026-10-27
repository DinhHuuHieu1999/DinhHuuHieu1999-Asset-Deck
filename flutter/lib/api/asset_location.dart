import 'asset.dart';
import 'asset_warranty.dart';

/// Optional manual location capability; legacy inventory stores remain unchanged.
abstract interface class AssetLocationSource {
  Future<AssetLocation> readLocation(String id);
  Future<AssetLocation> updateLocation(
    AssetLocation original,
    String? location,
  );
  Future<AssetLocationPage> listLocations({
    required String query,
    required String status,
    String category = '',
    required int offset,
    String locationMode = 'all',
    String? location,
    String warranty = '',
    String asOf = '',
  });
}

/// Normalize a human-entered label, rejecting controls and unpaired UTF-16 units.
String? normalizeAssetLocation(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('Invalid asset location');
  final label = value.trim();
  if (label.isEmpty ||
      label.length > 120 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(label)) {
    throw const FormatException('Invalid asset location');
  }
  for (var i = 0; i < label.length; i++) {
    final unit = label.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= label.length ||
          label.codeUnitAt(i) < 0xdc00 ||
          label.codeUnitAt(i) > 0xdfff) {
        throw const FormatException('Invalid asset location');
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const FormatException('Invalid asset location');
    }
  }
  return label;
}

/// Server identity and shared version; null is an explicitly unknown location.
class AssetLocation {
  const AssetLocation({
    required this.id,
    required this.version,
    required this.location,
  });
  final String id;
  final int version;
  final String? location;

  factory AssetLocation.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final version = json['version'];
    final location = normalizeAssetLocation(json['location']);
    if (json.length != 3 ||
        !json.containsKey('location') ||
        id is! String ||
        !RegExp(
          r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
        ).hasMatch(id) ||
        version is! int ||
        version < 1 ||
        version > 2147483647 ||
        location != json['location']) {
      throw const FormatException('Invalid asset location response');
    }
    return AssetLocation(id: id, version: version, location: location);
  }

  /// Serialize exactly the loaded version and an explicit location replacement.
  Map<String, Object?> replacement(String? value) {
    // Validate even manually constructed originals before touching the transport.
    AssetLocation.fromJson({
      'id': id,
      'version': version,
      'location': location,
    });
    if (version >= 2147483647)
      throw const FormatException('Invalid asset version');
    return {'version': version, 'location': normalizeAssetLocation(value)};
  }
}

/// One location-aware row without changing the legacy asset JSON contract.
class AssetLocationEntry {
  const AssetLocationEntry(this.asset, this.location);
  final AssetRecord asset;
  final String? location;
}

/// Bounded page validated with the established continuation and identity rules.
class AssetLocationPage {
  AssetLocationPage(
    List<AssetLocationEntry> items,
    this.nextOffset, {
    this.warrantyPage,
  }) : items = List.unmodifiable(items);
  final List<AssetLocationEntry> items;
  final int? nextOffset;
  final AssetWarrantyPage? warrantyPage;

  factory AssetLocationPage.fromJson(
    Map<String, Object?> json, {
    required int offset,
    String warranty = '',
    String asOf = '',
  }) {
    final page = AssetPage.fromJson(json, offset: offset);
    final raw = json['items'] as List;
    final items = <AssetLocationEntry>[];
    for (var i = 0; i < page.items.length; i++) {
      final row = raw[i] as Map<String, Object?>;
      final location = normalizeAssetLocation(row['location']);
      if (!row.containsKey('location') || row['location'] != location) {
        throw const FormatException('Invalid asset location page');
      }
      items.add(AssetLocationEntry(page.items[i], location));
    }
    AssetWarrantyPage? warrantyPage;
    if (warranty.isNotEmpty) {
      final stripped = raw
          .map(
            (value) =>
                Map<String, Object?>.from(value as Map)..remove('location'),
          )
          .toList();
      warrantyPage = AssetWarrantyPage.fromJson(
        {...json, 'items': stripped},
        offset: offset,
        warranty: warranty,
        asOf: asOf,
      );
    } else if (json.containsKey('warranty') ||
        json.containsKey('asOf') ||
        json.containsKey('through')) {
      throw const FormatException('Unexpected warranty metadata');
    }
    return AssetLocationPage(
      items,
      page.nextOffset,
      warrantyPage: warrantyPage,
    );
  }
}

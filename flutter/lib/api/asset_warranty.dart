import 'asset.dart';
import 'asset_dates.dart';

const assetWarrantyFilters = ['expired', 'expiring_soon'];

/// Optional capability, independent of the legacy inventory store.
abstract interface class AssetWarrantySource {
  Future<AssetWarrantyPage> listWarranty({
    String sort = 'updated_desc',
    required String query,
    required String status,
    String category = '',
    required String warranty,
    String asOf = '',
    required int offset,
  });
}

/// Gregorian horizon shared by response validation, not a local timezone date.
String assetWarrantyThrough(String asOf) {
  if (!isAssetCalendarDate(asOf)) {
    throw const FormatException('Invalid warranty reference date');
  }
  final date = DateTime.utc(
    int.parse(asOf.substring(0, 4)),
    int.parse(asOf.substring(5, 7)),
    int.parse(asOf.substring(8, 10)),
  );
  final end = date.add(const Duration(days: 30));
  if (end.year > 9999) return '9999-12-31';
  return '${end.year.toString().padLeft(4, '0')}-'
      '${end.month.toString().padLeft(2, '0')}-'
      '${end.day.toString().padLeft(2, '0')}';
}

/// Base fields and dates from the same list statement and shared version.
class AssetWarrantyItem {
  const AssetWarrantyItem(this.asset, this.dates);
  final AssetRecord asset;
  final AssetDatesInput dates;
}

/// A bounded warranty page whose echoed calendar and predicate are verified.
class AssetWarrantyPage {
  AssetWarrantyPage._(
    List<AssetWarrantyItem> items,
    this.nextOffset,
    this.warranty,
    this.asOf,
    this.through,
  ) : items = List.unmodifiable(items);
  final List<AssetWarrantyItem> items;
  final int? nextOffset;
  final String warranty, asOf, through;

  factory AssetWarrantyPage.fromJson(
    Map<String, Object?> json, {
    required String warranty,
    required String asOf,
    required int offset,
  }) {
    const fields = {'items', 'nextOffset', 'warranty', 'asOf', 'through'};
    final day = json['asOf'];
    if (json.length != fields.length ||
        !fields.every(json.containsKey) ||
        !assetWarrantyFilters.contains(warranty) ||
        json['warranty'] != warranty ||
        day is! String ||
        !isAssetCalendarDate(day) ||
        (asOf.isNotEmpty && day != asOf) ||
        json['through'] != assetWarrantyThrough(day) ||
        offset < 0 ||
        offset > 100000 ||
        (offset > 0 && asOf.isEmpty)) {
      throw const FormatException('Invalid warranty page reference');
    }
    final page = AssetPage.fromJson(json, offset: offset);
    final rows = json['items']! as List;
    const recordFields = {
      'id',
      'name',
      'category',
      'serial',
      'status',
      'notes',
      'version',
      'createdAt',
      'updatedAt',
      'purchasedOn',
      'warrantyExpiresOn',
    };
    final items = <AssetWarrantyItem>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i] as Map<String, Object?>;
      if (row.length != recordFields.length ||
          !recordFields.every(row.containsKey)) {
        throw const FormatException('Invalid warranty item');
      }
      final dates = AssetDates.fromJson({
        'id': row['id'],
        'version': row['version'],
        'purchasedOn': row['purchasedOn'],
        'warrantyExpiresOn': row['warrantyExpiresOn'],
      }).input;
      final end = dates.warrantyExpiresOn;
      if (end == null ||
          (warranty == 'expired'
              ? end.compareTo(day) >= 0
              : end.compareTo(day) < 0 ||
                    end.compareTo(json['through']! as String) > 0)) {
        throw const FormatException('Item does not match warranty filter');
      }
      items.add(AssetWarrantyItem(page.items[i], dates));
    }
    return AssetWarrantyPage._(
      items,
      page.nextOffset,
      warranty,
      day,
      json['through']! as String,
    );
  }
}

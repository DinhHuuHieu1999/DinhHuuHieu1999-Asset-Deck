import 'asset.dart';
import 'asset_check.dart';
import 'asset_dates.dart';
import 'asset_location.dart';
import 'asset_store.dart';

/// Optional values verified against the selected inventory snapshot version.
class AssetDetailsSnapshot {
  const AssetDetailsSnapshot({this.dates, this.location, this.checkDate});
  final AssetCheck? checkDate;
  final AssetDates? dates;
  final AssetLocation? location;

  /// Read enabled capabilities once; never merge different asset versions.
  static Future<AssetDetailsSnapshot> load(
    AssetRecord record, {
    AssetCheckSource? checkSource,
    AssetDatesSource? datesSource,
    AssetLocationSource? locationSource,
    bool Function()? isCurrent,
  }) async {
    void current() {
      if (isCurrent != null && !isCurrent()) {
        throw const AssetFailure('Session or detail context changed.');
      }
    }

    current();
    final dates = await datesSource?.readDates(record.id);
    current();
    if (dates != null) {
      AssetDates.fromJson({
        'id': dates.id,
        'version': dates.version,
        'purchasedOn': dates.input.purchasedOn,
        'warrantyExpiresOn': dates.input.warrantyExpiresOn,
      });
      _match(record, dates.id, dates.version);
    }
    final location = await locationSource?.readLocation(record.id);
    current();
    if (location != null) {
      AssetLocation.fromJson({
        'id': location.id,
        'version': location.version,
        'location': location.location,
      });
      _match(record, location.id, location.version);
    }
    final checkDate = await checkSource?.readCheckDate(record.id);
    current();
    if (checkDate != null) {
      AssetCheck.fromJson({
        'id': checkDate.id,
        'version': checkDate.version,
        'lastCheckedOn': checkDate.lastCheckedOn,
      });
      _match(record, checkDate.id, checkDate.version);
    }
    return AssetDetailsSnapshot(
      dates: dates,
      location: location,
      checkDate: checkDate,
    );
  }

  static void _match(AssetRecord record, String id, int version) {
    if (record.id.toLowerCase() != id.toLowerCase() ||
        record.version != version) {
      throw const AssetFailure(
        'Asset changed or is unavailable. Refresh inventory and reopen details.',
      );
    }
  }
}

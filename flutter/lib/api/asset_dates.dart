/// Optional capability; legacy inventory stores do not need date support.
abstract interface class AssetDatesSource {
  Future<AssetDates> readDates(String id);
  Future<AssetDates> updateDates(AssetDates original, AssetDatesInput input);
}

/// A date-only Gregorian value, never converted through a local timezone.
bool isAssetCalendarDate(Object? value) {
  if (value is! String ||
      value.length != 10 ||
      !RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$').hasMatch(value)) {
    return false;
  }
  final year = int.parse(value.substring(0, 4));
  final month = int.parse(value.substring(5, 7));
  final day = int.parse(value.substring(8, 10));
  if (year < 1 || month < 1 || month > 12 || day < 1) return false;
  final leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
  final days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return day <= days[month - 1];
}

/// Explicit nullable fields distinguish clearing dates from an omitted update.
class AssetDatesInput {
  const AssetDatesInput({
    required this.purchasedOn,
    required this.warrantyExpiresOn,
  });
  final String? purchasedOn, warrantyExpiresOn;

  /// Validate without trimming, date rollover, or silently reordering dates.
  void validate() {
    if ((purchasedOn != null && !isAssetCalendarDate(purchasedOn)) ||
        (warrantyExpiresOn != null &&
            !isAssetCalendarDate(warrantyExpiresOn)) ||
        (purchasedOn != null &&
            warrantyExpiresOn != null &&
            warrantyExpiresOn!.compareTo(purchasedOn!) < 0)) {
      throw const FormatException('Invalid purchase/warranty dates');
    }
  }

  /// Use the shared asset version; never include identity or owner in the body.
  Map<String, Object?> toJson({required int version}) {
    validate();
    if (version < 1 || version > 2147483646) {
      throw const FormatException('Invalid asset version');
    }
    return {
      'version': version,
      'purchasedOn': purchasedOn,
      'warrantyExpiresOn': warrantyExpiresOn,
    };
  }
}

/// Server-owned identity and shared version for the separate dates endpoint.
class AssetDates {
  const AssetDates({
    required this.id,
    required this.version,
    required this.input,
  });
  final String id;
  final int version;
  final AssetDatesInput input;

  factory AssetDates.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final version = json['version'];
    if (json.length != 4 ||
        id is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(id) ||
        version is! int ||
        version < 1 ||
        version > 2147483647 ||
        !json.containsKey('purchasedOn') ||
        !json.containsKey('warrantyExpiresOn') ||
        (json['purchasedOn'] != null && json['purchasedOn'] is! String) ||
        (json['warrantyExpiresOn'] != null &&
            json['warrantyExpiresOn'] is! String)) {
      throw const FormatException('Invalid asset dates response');
    }
    final input = AssetDatesInput(
      purchasedOn: json['purchasedOn'] as String?,
      warrantyExpiresOn: json['warrantyExpiresOn'] as String?,
    );
    input.validate();
    return AssetDates(id: id, version: version, input: input);
  }
}

/// Optional advisory lookup; never reserves a serial or blocks a write.
abstract interface class AssetSerialCheckSource {
  Future<bool> serialDuplicate(String serial, {String? excludeId});
}

/// Accept only the complete documented boolean response.
bool parseAssetSerialCheck(Object? value) {
  if (value is! Map || value.length != 1 || value['duplicate'] is! bool) {
    throw const FormatException('Invalid serial check response');
  }
  return value['duplicate'] as bool;
}

import 'package:flutter_test/flutter_test.dart';

import '../lib/api/asset_serial_check.dart';

void main() {
  test('accepts only explicit true and false', () {
    expect(parseAssetSerialCheck({'duplicate': true}), isTrue);
    expect(parseAssetSerialCheck({'duplicate': false}), isFalse);
  });
  test('malformed results never become no duplicate', () {
    for (final value in [
      null,
      <Object?>[],
      <String, Object?>{},
      {'duplicate': null},
      {'duplicate': 0},
      {'duplicate': 'false'},
      {'duplicate': false, 'extra': true},
    ]) {
      expect(() => parseAssetSerialCheck(value), throwsFormatException);
    }
  });
}

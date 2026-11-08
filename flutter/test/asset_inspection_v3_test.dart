import 'dart:convert';
import 'dart:typed_data';

import 'package:asset_desk/api/asset_inspection.dart';
import 'package:flutter_test/flutter_test.dart';

import 'asset_export_v3_test.dart' show exportV3Fixture;

void main() {
  final raw = Uint8List.fromList(utf8.encode(jsonEncode(exportV3Fixture())));
  final envelope = jsonDecode(utf8.decode(raw)) as Map<String, Object?>;
  var calls = 0;
  Future<String> digest(Uint8List bytes) async {
    calls++;
    expect(bytes, utf8.encode(envelope['payload']! as String));
    return envelope['sha256']! as String;
  }

  setUp(() => calls = 0);

  test(
    'inspects bounded exact-byte envelope using existing record parser',
    () async {
      final result = await inspectAssetV3Bytes(raw, digest: digest);
      expect(result.count, 1);
      expect(calls, 1);
      expect(() => result.records.clear(), throwsUnsupportedError);
    },
  );

  test('rejects oversized or invalid UTF-8 before hashing', () async {
    for (final bytes in [
      Uint8List(1024 * 1024 + 1),
      Uint8List.fromList([255]),
      Uint8List(0),
    ]) {
      await expectLater(
        inspectAssetV3Bytes(bytes, digest: digest),
        throwsFormatException,
      );
    }
    expect(calls, 0);
  });

  test(
    'rejects BOM and non-object or duplicate outer keys before hashing',
    () async {
      for (final bytes in [
        Uint8List.fromList([239, 187, 191, ...raw]),
        Uint8List.fromList(utf8.encode('[]')),
        Uint8List.fromList(utf8.encode('{"format":"x","format":"y"}')),
      ]) {
        await expectLater(
          inspectAssetV3Bytes(bytes, digest: digest),
          throwsFormatException,
        );
      }
      expect(calls, 0);
    },
  );

  test('rejects changed payload checksum without yielding preview', () async {
    await expectLater(
      inspectAssetV3Bytes(raw, digest: (_) async => '0' * 64),
      throwsFormatException,
    );
  });
}

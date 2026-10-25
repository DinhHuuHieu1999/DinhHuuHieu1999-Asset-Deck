import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../tool/export_https_acceptance.dart';

void main() {
  test('digest output requires exact lowercase SHA-256 and newline', () {
    final digest = 'a' * 64;
    expect(parseDigestOutput(utf8.encode('$digest\n')), digest);
    for (final value in [
      digest,
      '$digest\r\n',
      '${'A' * 64}\n',
      '${'z' * 64}\n',
    ]) {
      expect(() => parseDigestOutput(utf8.encode(value)), throwsA(anything));
    }
    expect(() => parseDigestOutput(List.filled(65, 255)), throwsA(anything));
  });

  test('Python bridge rejects implicit or nonexistent executables', () {
    for (final value in ['python', '', 'missing-python.exe']) {
      expect(() => validatePython(value), throwsA(anything));
    }
  });
  final python = Platform.environment['ASSET_EXPORT_TEST_PYTHON'];
  test(
    'opt-in real Python bridge hashes binary stdin without network',
    () async {
      expect(
        await pythonDigest(python!, Uint8List(0)),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      expect(
        await pythonDigest(python, Uint8List.fromList(utf8.encode('abc'))),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      await expectLater(
        pythonDigest(python, Uint8List(1024 * 1024 + 1)),
        throwsA(anything),
      );
    },
    skip: python == null ? 'Explicit local Python executable required' : false,
  );
}

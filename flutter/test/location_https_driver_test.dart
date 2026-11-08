import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/location_https_acceptance.dart' show validateLocationDriverArgs;

void main() {
  List<String> args() => [
    '--synthetic-only',
    'https://localhost:29443/api/v1',
    'a' * 32,
    Platform.resolvedExecutable,
  ];
  test(
    'explicit fixture arguments validate without network or process execution',
    () {
      expect(validateLocationDriverArgs(args()).port, 29443);
    },
  );
  test('missing or extra arguments refuse', () {
    expect(() => validateLocationDriverArgs([]), throwsA(anything));
    expect(
      () => validateLocationDriverArgs([...args(), 'extra']),
      throwsA(anything),
    );
  });
  test(
    'regular endpoints, non-TLS, invalid marker and missing executable refuse',
    () {
      for (final endpoint in [
        'https://localhost:8443/api/v1',
        'https://localhost:28443/api/v1',
        'http://localhost:29443/api/v1',
        'https://example.com:29443/api/v1',
        'https://localhost:29443/api/v1?owner=other',
      ]) {
        final input = args()..[1] = endpoint;
        expect(() => validateLocationDriverArgs(input), throwsA(anything));
      }
      expect(
        () => validateLocationDriverArgs(args()..[2] = 'invalid'),
        throwsA(anything),
      );
      expect(
        () => validateLocationDriverArgs(args()..[3] = 'python'),
        throwsA(anything),
      );
    },
  );
}

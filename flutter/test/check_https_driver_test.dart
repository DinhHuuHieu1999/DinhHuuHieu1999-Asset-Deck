import 'package:flutter_test/flutter_test.dart';

import '../tool/check_https_acceptance.dart' show validateCheckDriverArgs;

void main() {
  List<String> args() => [
    '--synthetic-only',
    'https://localhost:29443/api/v1',
    'a' * 32,
  ];
  test('exact synthetic endpoint and marker validate without network', () {
    expect(validateCheckDriverArgs(args()).port, 29443);
  });
  test('missing, extra or invalid opt-in arguments refuse', () {
    for (final value in [
      <String>[],
      [...args(), 'extra'],
      args()..[0] = 'execute',
      args()..[2] = 'invalid',
    ]) {
      expect(() => validateCheckDriverArgs(value), throwsA(anything));
    }
  });
  test('normal ports, remote targets, non-TLS and ambiguous URLs refuse', () {
    for (final endpoint in [
      'https://localhost:8443/api/v1',
      'https://localhost:28443/api/v1',
      'http://localhost:29443/api/v1',
      'https://example.com:29443/api/v1',
      'https://localhost:29443/api/v1?owner=other',
      'https://localhost:29443/api/v1#fragment',
      'https://user:password@localhost:29443/api/v1',
    ]) {
      expect(
        () => validateCheckDriverArgs(args()..[1] = endpoint),
        throwsA(anything),
      );
    }
  });
}

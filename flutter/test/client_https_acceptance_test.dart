import 'package:flutter_test/flutter_test.dart';

import '../tool/client_https_acceptance.dart' as driver;

void main() {
  const id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  test('driver rejects missing opt-in and non-fixture targets without IO', () {
    for (final args in <List<String>>[
      [],
      ['https://localhost:19003/api/v1', id],
      ['--synthetic-only', 'http://localhost:19003/api/v1', id],
      ['--synthetic-only', 'https://example.com:19003/api/v1', id],
      ['--synthetic-only', 'https://localhost:8443/api/v1', id],
      ['--synthetic-only', 'https://localhost:19003/api/v1?x=1', id],
      ['--synthetic-only', 'https://user:secret@localhost:19003/api/v1', id],
      ['--synthetic-only', 'https://localhost:19003/api/v1', 'wrong'],
    ]) {
      expect(() => driver.validateDriverArgs(args), throwsA(anything));
    }
    expect(
      driver.validateDriverArgs([
        '--synthetic-only',
        'https://localhost:19003/api/v1',
        id,
      ]).port,
      19003,
    );
  });
  test('only matching synthetic marker allows progression', () {
    for (final value in [
      null,
      <Object?>[],
      <String, Object?>{},
      {'fixtureId': id},
      {'fixtureId': 'wrong', 'syntheticOnly': true},
      {'fixtureId': id, 'syntheticOnly': false},
    ]) {
      expect(() => driver.validateMarker(value, id), throwsStateError);
    }
    driver.validateMarker({'fixtureId': id, 'syntheticOnly': true}, id);
  });
  test(
    'conflict check rejects success and all other failure statuses',
    () async {
      expect(driver.conflict(() async => null), throwsStateError);
    },
  );
}

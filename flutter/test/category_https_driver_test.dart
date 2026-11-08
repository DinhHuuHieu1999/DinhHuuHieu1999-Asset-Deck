import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/category_https_acceptance.dart' as driver;

void main() {
  test(
    'category driver refuses missing opt-in before contacting a target',
    () async {
      final previous = exitCode;
      try {
        await driver.main([]);
        expect(exitCode, 1);
      } finally {
        exitCode = previous;
      }
    },
  );
  test(
    'category driver refuses regular endpoint before client registration',
    () async {
      final previous = exitCode;
      try {
        await driver.main([
          '--synthetic-only',
          'https://localhost:8443/api/v1',
          'a' * 32,
        ]);
        expect(exitCode, 1);
      } finally {
        exitCode = previous;
      }
    },
  );
}

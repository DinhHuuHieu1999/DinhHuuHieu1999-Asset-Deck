import 'package:flutter_test/flutter_test.dart';

import '../tool/check_sort_https_acceptance.dart' show compareCheckSortEntries;

void main() {
  test('old dates precede new dates and Unknown; equal dates use ID', () {
    final rows = <(String, String?)>[
      ('b', null),
      ('c', '2024-02-29'),
      ('z', '2023-12-31'),
      ('a', null),
      ('a', '2023-12-31'),
    ]..sort(compareCheckSortEntries);
    expect(rows, [
      ('a', '2023-12-31'),
      ('z', '2023-12-31'),
      ('c', '2024-02-29'),
      ('a', null),
      ('b', null),
    ]);
  });
}

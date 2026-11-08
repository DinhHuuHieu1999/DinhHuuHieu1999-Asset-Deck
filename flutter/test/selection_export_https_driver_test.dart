import 'package:flutter_test/flutter_test.dart';

import '../tool/selection_export_https_acceptance.dart'
    show validateSelectionHttp;

void main() {
  test('raw HTTP contract requires success no-store and query refusal', () {
    validateSelectionHttp(200, 'no-store', query: false);
    validateSelectionHttp(400, null, query: true);
    for (final code in [301, 401, 403, 404, 500]) {
      expect(
        () => validateSelectionHttp(code, 'no-store', query: false),
        throwsStateError,
      );
      expect(
        () => validateSelectionHttp(code, null, query: true),
        throwsStateError,
      );
    }
    for (final header in [null, '', 'public', 'max-age=3600']) {
      expect(
        () => validateSelectionHttp(200, header, query: false),
        throwsStateError,
      );
    }
    expect(
      () => validateSelectionHttp(200, 'no-store', query: true),
      throwsStateError,
    );
  });
}

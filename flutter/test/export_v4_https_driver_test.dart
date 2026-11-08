import 'package:flutter_test/flutter_test.dart';

import '../tool/export_v4_https_acceptance.dart' show validateExportV4Http;

void main() {
  test('raw HTTP contract requires success no-store and query refusal', () {
    validateExportV4Http(200, 'no-store', query: false);
    validateExportV4Http(400, null, query: true);
    for (final code in [301, 401, 403, 404, 500]) {
      expect(
        () => validateExportV4Http(code, 'no-store', query: false),
        throwsStateError,
      );
      expect(
        () => validateExportV4Http(code, null, query: true),
        throwsStateError,
      );
    }
    for (final header in [null, '', 'public', 'max-age=3600']) {
      expect(
        () => validateExportV4Http(200, header, query: false),
        throwsStateError,
      );
    }
    expect(
      () => validateExportV4Http(200, 'no-store', query: true),
      throwsStateError,
    );
  });
}

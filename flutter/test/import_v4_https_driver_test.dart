import 'dart:convert';

import '../lib/api/asset_export_v4.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/import_v4_https_acceptance.dart' show verifyReexport;
import 'asset_export_v4_test.dart' show exportV4Fixture;

void main() {
  const id = '12345678-1234-4123-8123-123456789abc';
  Future<AssetExportV4> snapshot({
    bool imported = false,
    String? date = '2024-03-01',
  }) async {
    final envelope = exportV4Fixture();
    final payload =
        jsonDecode(envelope['payload']! as String) as Map<String, dynamic>;
    final row = (payload['records'] as List).single as Map<String, dynamic>;
    if (imported) {
      row['id'] = id;
      row['version'] = 1;
    }
    row['lastCheckedDate'] = date;
    envelope['payload'] = jsonEncode(payload);
    return AssetExportV4.parse(envelope, digest: (_) async => 'a' * 64);
  }

  test(
    'reexport assertion accepts exact stored fields with new identity',
    () async {
      verifyReexport(await snapshot(), await snapshot(imported: true), [id]);
    },
  );
  test('reexport assertion refuses changed manual date', () async {
    final source = await snapshot();
    final target = await snapshot(imported: true, date: '2024-03-02');
    expect(() => verifyReexport(source, target, [id]), throwsA(anything));
  });
  test('reexport assertion refuses lost nullable date', () async {
    final source = await snapshot();
    final target = await snapshot(imported: true, date: null);
    expect(() => verifyReexport(source, target, [id]), throwsA(anything));
  });
}

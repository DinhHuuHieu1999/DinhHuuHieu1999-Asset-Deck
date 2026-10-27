import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../lib/api/asset_export_v2.dart';

import '../tool/import_v2_https_acceptance.dart' show verifyReexport;
import 'asset_export_v2_test.dart' show exportV2Fixture;

void main() {
  Future<AssetExportV2> snapshot(Map<String, Object?> patch) async {
    final envelope = exportV2Fixture();
    final payload =
        jsonDecode(envelope['payload']! as String) as Map<String, dynamic>;
    final rows = payload['records'] as List;
    rows[0] = {...rows[0] as Map<String, dynamic>, ...patch};
    envelope['payload'] = jsonEncode(payload);
    return AssetExportV2.parse(envelope, digest: (_) async => 'a' * 64);
  }

  test(
    're-export check accepts fresh identity and all retained fields',
    () async {
      final original = await snapshot({});
      final target = await snapshot({
        'id': '12345678-1234-4234-8234-123456789abc',
        'version': 1,
      });
      verifyReexport(original, target, [target.records.single.asset.id]);
    },
  );
  test(
    're-export check refuses lost fields, dates, version or identity',
    () async {
      final original = await snapshot({});
      const id = '12345678-1234-4234-8234-123456789abc';
      for (final change in <Map<String, Object?>>[
        {'name': 'Changed'},
        {'category': 'Changed'},
        {'serial': 'Changed'},
        {'notes': 'Changed'},
        {'status': 'repair'},
        {'purchasedOn': null},
        {'warrantyExpiresOn': null},
        {'version': 2},
        {'id': original.records.single.asset.id},
      ]) {
        final target = await snapshot({'id': id, 'version': 1, ...change});
        expect(
          () => verifyReexport(original, target, [
            target.records.single.asset.id,
          ]),
          throwsA(anything),
        );
      }
    },
  );
}

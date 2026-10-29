import 'dart:convert';
import 'dart:typed_data';

import 'package:asset_desk/api/asset_inspection.dart';
import 'package:flutter_test/flutter_test.dart';

import 'asset_selection_export_test.dart' show selectionFixture;
import 'asset_export_v3_test.dart' show exportV3Fixture;

void main() {
  test(
    'inspects exact payload bytes and preserves immutable selection scope',
    () async {
      final envelope = selectionFixture();
      var calls = 0;
      final result = await inspectAssetSelectionBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
        digest: (bytes) async {
          calls++;
          expect(bytes, utf8.encode(envelope['payload']! as String));
          return envelope['sha256']! as String;
        },
      );
      expect(result.count, 1);
      expect(calls, 1);
      expect(result.scope.toQuery()['q'], '%_');
      expect(() => result.records.clear(), throwsUnsupportedError);
    },
  );

  test('rejects invalid bytes and ambiguous envelopes before digest', () async {
    var calls = 0;
    final raw = utf8.encode(jsonEncode(selectionFixture()));
    for (final bytes in [
      Uint8List(0),
      Uint8List(1024 * 1024 + 1),
      Uint8List.fromList([255, 255]),
      Uint8List.fromList([239, 187, 191, ...raw]),
      Uint8List.fromList(utf8.encode('[]')),
      Uint8List.fromList(utf8.encode('{"format":"x","format":"y"}')),
    ]) {
      await expectLater(
        inspectAssetSelectionBytes(
          bytes,
          digest: (_) async {
            calls++;
            return 'a' * 64;
          },
        ),
        throwsFormatException,
      );
    }
    expect(calls, 0);
  });

  test('checksum mismatch never yields a selection preview', () async {
    await expectLater(
      inspectAssetSelectionBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(selectionFixture()))),
        digest: (_) async => '0' * 64,
      ),
      throwsFormatException,
    );
  });

  test('selection file cannot be inspected as a full export', () async {
    final bytes = Uint8List.fromList(
      utf8.encode(jsonEncode(selectionFixture())),
    );
    for (final inspect in [inspectAssetBytes, inspectAssetV3Bytes]) {
      await expectLater(
        inspect(bytes, digest: (_) async => 'a' * 64),
        throwsFormatException,
      );
    }
  });
  test(
    'full inventory format is rejected by selection inspector before hashing',
    () async {
      var calls = 0;
      await expectLater(
        inspectAssetSelectionBytes(
          Uint8List.fromList(utf8.encode(jsonEncode(exportV3Fixture()))),
          digest: (_) async {
            calls++;
            return 'a' * 64;
          },
        ),
        throwsFormatException,
      );
      expect(calls, 0);
    },
  );

  test('digest failure cannot produce trusted selection evidence', () async {
    await expectLater(
      inspectAssetSelectionBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(selectionFixture()))),
        digest: (_) async => throw StateError('Synthetic digest unavailable'),
      ),
      throwsA(isA<StateError>()),
    );
  });
}

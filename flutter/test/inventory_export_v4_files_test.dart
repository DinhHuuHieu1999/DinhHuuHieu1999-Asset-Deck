import 'dart:convert';

import 'package:asset_desk/api/asset_export_v4.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:asset_desk/inventory_export_files.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'asset_export_v4_test.dart' show exportV4Fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('asset_desk/inventory_export');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final outcome in [true, null, false, 'unexpected']) {
    test('v4 native boundary preserves exact bytes: $outcome', () async {
      final snapshot = await AssetExportV4.parse(
        exportV4Fixture(),
        digest: (_) async => 'a' * 64,
      );
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return outcome;
      });
      final files = WindowsInventoryExportFiles();
      if (outcome == true || outcome == null) {
        expect(await files.saveV4(snapshot), outcome == true);
      } else {
        await expectLater(files.saveV4(snapshot), throwsA(isA<AssetFailure>()));
      }
      expect(calls, hasLength(1));
      expect(calls.single.method, 'saveJson');
      expect(utf8.decode(calls.single.arguments as Uint8List), snapshot.json);
    });
  }

  test('v4 existing destination fails without automatic retry', () async {
    final snapshot = await AssetExportV4.parse(
      exportV4Fixture(),
      digest: (_) async => 'a' * 64,
    );
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      throw PlatformException(code: 'file_exists');
    });
    await expectLater(
      WindowsInventoryExportFiles().saveV4(snapshot),
      throwsA(
        isA<AssetFailure>().having(
          (failure) => failure.message,
          'safe error',
          contains('nothing was overwritten'),
        ),
      ),
    );
    expect(calls, 1);
  });
}

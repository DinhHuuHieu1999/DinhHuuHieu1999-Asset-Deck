import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset_selection_csv.dart';
import 'package:asset_desk/api/asset_selection_export_v2.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:asset_desk/inventory_export_files.dart';

import 'asset_selection_export_v2_test.dart' show selectionV2Fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('asset_desk/inventory_export');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  for (final outcome in [true, null, false]) {
    test('CSV fixed channel and exact UTF-8 bytes, outcome $outcome', () async {
      final snapshot = await AssetSelectionExportV2.parse(
        selectionV2Fixture(),
        digest: (_) async => 'a' * 64,
      );
      final csv = AssetSelectionCsv.fromSelection(snapshot);
      var count = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        count++;
        expect(call.method, 'saveSelectionCsv');
        expect(utf8.decode(call.arguments as Uint8List), csv.text);
        return outcome;
      });
      final save = WindowsInventoryExportFiles().saveSelectionCsv(csv);
      if (outcome == false) {
        await expectLater(save, throwsA(isA<AssetFailure>()));
      } else {
        expect(await save, outcome == true);
      }
      expect(count, 1);
    });
  }
  test('existing-file error refuses overwrite without retry', () async {
    final snapshot = await AssetSelectionExportV2.parse(
      selectionV2Fixture(),
      digest: (_) async => 'a' * 64,
    );
    var count = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      count++;
      throw PlatformException(code: 'file_exists');
    });
    await expectLater(
      WindowsInventoryExportFiles().saveSelectionCsv(
        AssetSelectionCsv.fromSelection(snapshot),
      ),
      throwsA(
        isA<AssetFailure>().having(
          (e) => e.message,
          'message',
          contains('nothing was overwritten'),
        ),
      ),
    );
    expect(count, 1);
  });
}

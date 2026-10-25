import 'package:asset_desk/api/asset_store.dart';
import 'package:asset_desk/inventory_inspection_files.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('asset_desk/inventory_export');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final files = WindowsInventoryInspectionFiles();
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'explicit choose sends no path and returns a defensive byte copy',
    () async {
      final bytes = Uint8List.fromList([123, 125]);
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        expect(call.method, 'chooseInspectionJson');
        expect(call.arguments, isNull);
        return bytes;
      });
      final result = await files.choose();
      expect(result, bytes);
      expect(calls, 1);
    },
  );
  test('cancel returns no bytes', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await files.choose(), isNull);
  });
  for (final result in [
    true,
    'private-path.json',
    Uint8List(1),
    Uint8List(1024 * 1024 + 1),
  ]) {
    test(
      'rejects invalid or oversized native selection ${result.runtimeType}',
      () async {
        messenger.setMockMethodCallHandler(channel, (_) async => result);
        await expectLater(files.choose(), throwsA(isA<AssetFailure>()));
      },
    );
  }
  test('native read error is generic and never retried', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      throw PlatformException(code: 'read_failed', message: 'private filename');
    });
    try {
      await files.choose();
      fail('Expected failure');
    } on AssetFailure catch (error) {
      expect(error.message, isNot(contains('private filename')));
    }
    expect(calls, 1);
  });
}

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset_import.dart';
import 'package:asset_desk/api/asset_import_recovery.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:asset_desk/inventory_recovery_files.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('asset_desk/inventory_export');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final files = WindowsInventoryRecoveryFiles();
  final calls = <MethodCall>[];
  Object? response;
  PlatformException? failure;
  setUp(() {
    calls.clear();
    response = null;
    failure = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (failure != null) throw failure!;
      return response;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  Future<AssetImportRecovery> recovery() => AssetImportRecovery.prepare(
    draft: AssetImportDraft.restore(
      accountId: 'abcdef0123456789abcdef01',
      requestJson: jsonEncode({
        'requestId': '12345678-1234-4123-8123-123456789abc',
        'records': [
          {
            'name': 'Fixture',
            'category': 'test',
            'serial': '',
            'status': 'stored',
            'notes': '',
          },
        ],
      }),
    ),
    apiBase: 'https://localhost/api/v1',
    digest: (_) async => 'a' * 64,
  );
  test('choose cancellation is null with no path argument', () async {
    expect(await files.choose(), isNull);
    expect(calls.single.method, 'chooseRecoveryJson');
    expect(calls.single.arguments, isNull);
  });
  test('bounded chosen bytes copied; malformed results refused', () async {
    response = Uint8List.fromList([123, 125]);
    expect(await files.choose(), [123, 125]);
    for (final value in [
      'private-path',
      true,
      Uint8List(1),
      Uint8List(2 * 1024 * 1024 + 1),
    ]) {
      response = value;
      await expectLater(files.choose(), throwsA(isA<AssetFailure>()));
    }
  });
  test('hash has separate method and 2 MiB bound', () async {
    response = 'a' * 64;
    expect(await files.digest(Uint8List(1024 * 1024 + 1)), response);
    expect(calls.single.method, 'sha256Recovery');
    calls.clear();
    await expectLater(
      files.digest(Uint8List(2 * 1024 * 1024 + 1)),
      throwsA(isA<AssetFailure>()),
    );
    expect(calls, isEmpty);
    response = 'invalid';
    await expectLater(files.digest(Uint8List(0)), throwsA(isA<AssetFailure>()));
  });
  test('save cancel does not mean saved; true only success', () async {
    final file = await recovery();
    expect(await files.save(file), isFalse);
    expect(calls.single.method, 'saveRecoveryJson');
    expect(utf8.decode(calls.single.arguments as Uint8List), file.json);
    response = true;
    expect(await files.save(file), isTrue);
    response = false;
    await expectLater(files.save(file), throwsA(isA<AssetFailure>()));
  });
  test('native failure stays failure, never returns success', () async {
    failure = PlatformException(code: 'file_exists');
    await expectLater(
      files.save(await recovery()),
      throwsA(isA<AssetFailure>()),
    );
    await expectLater(files.choose(), throwsA(isA<AssetFailure>()));
    await expectLater(files.digest(Uint8List(0)), throwsA(isA<AssetFailure>()));
  });
  test('missing plugin refused instead of silent fallback', () async {
    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(files.choose(), throwsA(isA<AssetFailure>()));
    await expectLater(files.digest(Uint8List(0)), throwsA(isA<AssetFailure>()));
    await expectLater(
      files.save(await recovery()),
      throwsA(isA<AssetFailure>()),
    );
  });
}

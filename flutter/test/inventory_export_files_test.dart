import 'dart:convert';
import 'dart:io';

import 'package:asset_desk/api/asset_export.dart';
import 'package:asset_desk/api/asset_export_v2.dart';
import 'package:asset_desk/api/asset_export_v3.dart';

import 'asset_export_v3_test.dart' show exportV3Fixture;

import 'asset_export_v2_test.dart' show exportV2Fixture;

import 'package:asset_desk/api/asset_store.dart';
import 'package:asset_desk/inventory_export_files.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('asset_desk/inventory_export');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final files = WindowsInventoryExportFiles();
  final fixture = jsonDecode(
    File('test/fixtures/inventory-export-v1.json').readAsStringSync(),
  ) as Map<String, Object?>;
  late List<MethodCall> calls;
  setUp(() {
    calls = [];
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'digest forwards exact bounded bytes and requires lowercase SHA-256',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return fixture['sha256'];
      });
      final bytes = Uint8List.fromList(
        utf8.encode(fixture['payload']! as String),
      );
      expect(await files.digest(bytes), fixture['sha256']);
      expect(calls.single.method, 'sha256');
      expect(calls.single.arguments, bytes);
      await expectLater(
        files.digest(Uint8List(1024 * 1024 + 1)),
        throwsA(isA<AssetFailure>()),
      );
      expect(calls.length, 1);
    },
  );
  for (final response in [null, '', 'A' * 64, 'z' * 64]) {
    test('rejects invalid native digest $response', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => response);
      await expectLater(
        files.digest(Uint8List(0)),
        throwsA(isA<AssetFailure>()),
      );
    });
  }
  for (final outcome in [true, null, false, 'unexpected']) {
    test('save handles result $outcome without auto retry', () async {
      final snapshot = await AssetExport.parse(
        fixture,
        digest: (_) async => fixture['sha256']! as String,
      );
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return outcome;
      });
      if (outcome == true || outcome == null) {
        expect(await files.save(snapshot), outcome == true);
      } else {
        await expectLater(files.save(snapshot), throwsA(isA<AssetFailure>()));
      }
      expect(calls.single.method, 'saveJson');
      expect(utf8.decode(calls.single.arguments as Uint8List), snapshot.json);
    });
  }
  test(
    'existing file maps to no-overwrite error without leaking native details',
    () async {
      final snapshot = await AssetExport.parse(
        fixture,
        digest: (_) async => fixture['sha256']! as String,
      );
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        throw PlatformException(code: 'file_exists', message: 'private path');
      });
      await expectLater(
        files.save(snapshot),
        throwsA(
          isA<AssetFailure>().having(
            (e) => e.message,
            'message',
            contains('nothing was overwritten'),
          ),
        ),
      );
      expect(calls.length, 1);
    },
  );
  for (final outcome in [true, null, false, 'unexpected']) {
    test(
      'v2 native save forwards exact bytes and handles $outcome once',
      () async {
        final snapshot = await AssetExportV2.parse(
          exportV2Fixture(),
          digest: (_) async => 'a' * 64,
        );
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return outcome;
        });
        if (outcome == true || outcome == null) {
          expect(await files.saveV2(snapshot), outcome == true);
        } else {
          await expectLater(
            files.saveV2(snapshot),
            throwsA(isA<AssetFailure>()),
          );
        }
        expect(calls.single.method, 'saveJson');
        expect(utf8.decode(calls.single.arguments as Uint8List), snapshot.json);
      },
    );
  }
  test(
    'v2 native existing file is refused without retry or path exposure',
    () async {
      final snapshot = await AssetExportV2.parse(
        exportV2Fixture(),
        digest: (_) async => 'a' * 64,
      );
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        throw PlatformException(code: 'file_exists', message: 'private path');
      });
      await expectLater(
        files.saveV2(snapshot),
        throwsA(
          isA<AssetFailure>().having(
            (e) => e.message,
            'safe message',
            allOf(
              contains('nothing was overwritten'),
              isNot(contains('private path')),
            ),
          ),
        ),
      );
      expect(calls.length, 1);
    },
  );
  for (final outcome in [true, null, false, 'unexpected']) {
    test(
      'v3 native save forwards exact bytes and handles $outcome once',
      () async {
        final snapshot = await AssetExportV3.parse(
          exportV3Fixture(),
          digest: (_) async => 'a' * 64,
        );
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return outcome;
        });
        if (outcome == true || outcome == null) {
          expect(await files.saveV3(snapshot), outcome == true);
        } else {
          await expectLater(
            files.saveV3(snapshot),
            throwsA(isA<AssetFailure>()),
          );
        }
        expect(calls.single.method, 'saveJson');
        expect(utf8.decode(calls.single.arguments as Uint8List), snapshot.json);
      },
    );
  }
  test(
    'v3 native existing file is refused without retry or path exposure',
    () async {
      final snapshot = await AssetExportV3.parse(
        exportV3Fixture(),
        digest: (_) async => 'a' * 64,
      );
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        throw PlatformException(code: 'file_exists', message: 'private path');
      });
      await expectLater(
        files.saveV3(snapshot),
        throwsA(
          isA<AssetFailure>().having(
            (e) => e.message,
            'safe message',
            allOf(
              contains('nothing was overwritten'),
              isNot(contains('private path')),
            ),
          ),
        ),
      );
      expect(calls.length, 1);
    },
  );
  test(
    'absent native handler reports unavailable rather than successful hash',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw MissingPluginException(),
      );
      await expectLater(
        files.digest(Uint8List(0)),
        throwsA(isA<AssetFailure>()),
      );
    },
  );
}

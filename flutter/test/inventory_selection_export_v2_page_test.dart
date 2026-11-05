import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset_export.dart';
import 'package:asset_desk/api/asset_selection_export_v2.dart';
import 'package:asset_desk/inventory_export_files.dart';
import 'package:asset_desk/inventory_selection_export_v2_page.dart';

import 'asset_selection_export_v2_test.dart' show selectionV2Fixture;

class Source implements AssetSelectionExportV2Source {
  Source(this.snapshot);
  final AssetSelectionExportV2 snapshot;
  bool fail = false;
  @override
  Future<AssetSelectionExportV2> exportSelectionV2({
    required AssetSelectionScopeV2 scope,
    required AssetExportDigest digest,
  }) async {
    if (fail) throw StateError('private');
    return snapshot;
  }
}

class Files implements InventorySelectionExportV2Files {
  int saves = 0;
  @override
  Future<String> digest(Uint8List bytes) async => 'a' * 64;
  @override
  Future<bool> saveSelectionV2(AssetSelectionExportV2 snapshot) async {
    saves++;
    return false;
  }
}

void main() {
  testWidgets(
    'explicit Prepare and save Cancel retain v2; failed prepare clears evidence',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final snapshot = await AssetSelectionExportV2.parse(
        selectionV2Fixture(),
        digest: (_) async => 'a' * 64,
      );
      final source = Source(snapshot), files = Files();
      await tester.pumpWidget(
        MaterialApp(
          home: InventorySelectionExportV2Page(
            source: source,
            files: files,
            scope: snapshot.scope,
          ),
        ),
      );
      expect(find.textContaining('Matching selection:'), findsNothing);
      await tester.tap(find.text('Prepare selection JSON'));
      await tester.pumpAndSettle();
      expect(find.text('Matching selection: 1 asset'), findsOneWidget);
      await tester.tap(find.text('Save selection JSON as... (Windows)'));
      await tester.pumpAndSettle();
      expect(files.saves, 1);
      expect(find.text('Matching selection: 1 asset'), findsOneWidget);
      source.fail = true;
      await tester.tap(find.text('Prepare selection JSON'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Matching selection:'), findsNothing);
      expect(find.text('Unable to prepare matching selection'), findsOneWidget);
    },
  );
  test(
    'native v2 save passes exact bytes to selection dialog, not full export',
    () async {
      const channel = MethodChannel('asset_desk/inventory_export');
      final snapshot = await AssetSelectionExportV2.parse(
        selectionV2Fixture(),
        digest: (_) async => 'a' * 64,
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'saveSelectionJson');
        expect(call.arguments, Uint8List.fromList(utf8.encode(snapshot.json)));
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      expect(
        await WindowsInventoryExportFiles().saveSelectionV2(snapshot),
        false,
      );
    },
  );

  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('selection render $width at 200 percent', (tester) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final font = Platform.environment['ASSET_DESK_UI_CAPTURE_FONT'];
      if (font != null) {
        final loader = FontLoader('SelectionCapture')
          ..addFont(
            Future.value(ByteData.sublistView(File(font).readAsBytesSync())),
          );
        await loader.load();
      }
      final snapshot = await AssetSelectionExportV2.parse(
        selectionV2Fixture(mode: 'before', date: '2024-02-29'),
        digest: (_) async => 'a' * 64,
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            fontFamily: font == null ? null : 'SelectionCapture',
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: key,
            child: InventorySelectionExportV2Page(
              source: Source(snapshot),
              files: Files(),
              scope: snapshot.scope,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prepare selection JSON'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final dir = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
      if (dir != null)
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$dir/selection-v2-${width.toInt()}-200.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
    });
  }
}

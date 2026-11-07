import 'package:asset_desk/api/asset_store.dart';
import 'package:asset_desk/api/asset_selection_csv.dart';

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

class Files
    implements InventorySelectionExportV2Files, InventorySelectionCsvFiles {
  int saves = 0;
  int csvSaves = 0;
  AssetSelectionCsv? csv;
  @override
  Future<bool> saveSelectionCsv(AssetSelectionCsv snapshot) async {
    csvSaves++;
    csv = snapshot;
    return false;
  }

  @override
  Future<String> digest(Uint8List bytes) async => 'a' * 64;
  @override
  Future<bool> saveSelectionV2(AssetSelectionExportV2 snapshot) async {
    saves++;
    return false;
  }
}

class CsvOutcomeFiles extends Files {
  CsvOutcomeFiles(this.fail);
  final bool fail;
  @override
  Future<bool> saveSelectionCsv(AssetSelectionCsv snapshot) async {
    csvSaves++;
    if (fail) throw const AssetFailure('Synthetic CSV write failure');
    return true;
  }
}

void main() {
  for (final fail in [false, true]) {
    testWidgets('CSV save outcome fail=$fail preserves prepared selection', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1100, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final snapshot = await AssetSelectionExportV2.parse(
        selectionV2Fixture(),
        digest: (_) async => 'a' * 64,
      );
      final files = CsvOutcomeFiles(fail);
      await tester.pumpWidget(
        MaterialApp(
          home: InventorySelectionExportV2Page(
            source: Source(snapshot),
            files: files,
            scope: snapshot.scope,
          ),
        ),
      );
      await tester.tap(find.text('Prepare selection JSON'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text('Save selection CSV as... (Windows)'),
      );
      await tester.tap(find.text('Save selection CSV as... (Windows)'));
      await tester.pumpAndSettle();
      expect(files.csvSaves, 1);
      expect(find.text('Matching selection: 1 asset'), findsOneWidget);
      expect(find.text('Save selection JSON as... (Windows)'), findsOneWidget);
      expect(
        find.textContaining(
          fail ? 'Synthetic CSV write failure' : 'CSV saved:',
        ),
        findsOneWidget,
      );
    });
  }
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

  testWidgets(
    'CSV uses prepared verified selection; Cancel keeps JSON and count',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 2000);
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
      expect(find.text('Save selection CSV as... (Windows)'), findsNothing);
      await tester.tap(find.text('Prepare selection JSON'));
      await tester.pumpAndSettle();
      source.fail = true;
      await tester.ensureVisible(
        find.text('Save selection CSV as... (Windows)'),
      );
      await tester.tap(find.text('Save selection CSV as... (Windows)'));
      await tester.pumpAndSettle();
      expect(files.csvSaves, 1);
      expect(files.csv!.count, 1);
      expect(files.saves, 0);
      expect(find.text('Matching selection: 1 asset'), findsOneWidget);
      expect(
        find.text('Save canceled. Prepared selection retained.'),
        findsOneWidget,
      );
      expect(find.text('Save selection JSON as... (Windows)'), findsOneWidget);
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

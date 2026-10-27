import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:asset_desk/api/asset_export.dart';
import 'package:asset_desk/api/asset_export_v3.dart';

import 'asset_export_v3_test.dart' show exportV3Fixture;
import 'assets_page_test.dart' show FakeStore;
import 'asset_desk_app_test.dart' show FakeSession, login;

import 'package:asset_desk/asset_desk_app.dart';

import 'package:asset_desk/assets_page.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:asset_desk/inventory_export_files.dart';
import 'package:asset_desk/inventory_export_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class ExportSource implements AssetExportV3Source {
  ExportSource(this.snapshot);
  final AssetExportV3 snapshot;
  int calls = 0;
  AssetFailure? error;
  Completer<AssetExportV3>? pending;
  @override
  Future<AssetExportV3> exportInventoryV3({
    required AssetExportDigest digest,
  }) async {
    calls++;
    if (error != null) throw error!;
    return pending == null ? snapshot : pending!.future;
  }
}

class ExportFiles implements InventoryExportFiles, InventoryExportV3Files {
  int saves = 0;
  bool saved = false;
  AssetFailure? error;
  @override
  Future<String> digest(Uint8List bytes) async => throw UnimplementedError();
  @override
  Future<bool> save(AssetExport snapshot) =>
      throw StateError('v1 must not run');
  @override
  Future<bool> saveV3(AssetExportV3 snapshot) async {
    saves++;
    if (error != null) throw error!;
    return saved;
  }
}

class V3Inventory extends FakeStore implements AssetExportV3Source {
  V3Inventory(this.snapshot);
  final AssetExportV3 snapshot;
  int exports = 0;
  @override
  Future<AssetExportV3> exportInventoryV3({
    required AssetExportDigest digest,
  }) async {
    exports++;
    return snapshot;
  }
}

class V3Session extends FakeSession implements AssetExportV3Source {
  V3Session(this.snapshot);
  final AssetExportV3 snapshot;
  Completer<AssetExportV3>? pending;
  @override
  Future<AssetExportV3> exportInventoryV3({
    required AssetExportDigest digest,
  }) async => pending?.future ?? snapshot;
}

void main() {
  late AssetExportV3 snapshot;
  setUpAll(() async {
    snapshot = await AssetExportV3.parse(
      exportV3Fixture(),
      digest: (_) async => 'a' * 64,
    );
  });
  Future<void> open(
    WidgetTester tester,
    ExportSource source,
    ExportFiles files,
  ) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryExportPage.v3(source: source, files: files),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final flags in [
    [false, true, true],
    [true, false, true],
    [true, true, false],
  ]) {
    testWidgets('v3 stays hidden when a prerequisite is disabled: $flags', (
      tester,
    ) async {
      final store = V3Inventory(snapshot);
      await tester.pumpWidget(
        MaterialApp(
          home: AssetsPage(
            store: store,
            enableInventoryExportV3: flags[0],
            enableAssetDates: flags[1],
            enableAssetLocation: flags[2],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Export JSON v3 with dates and location'), findsNothing);
      expect(
        find.text('Inspect JSON v3 with location (no import)'),
        findsNothing,
      );
      expect(store.exports, 0);
    });
  }

  testWidgets('v3 navigation requires explicit flags and source capability', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = V3Inventory(snapshot);
    final files = ExportFiles();
    await tester.pumpWidget(
      MaterialApp(
        home: AssetsPage(store: store, exportFiles: files),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Export JSON v3 with dates and location'), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        home: AssetsPage(
          store: FakeStore(),
          enableInventoryExportV3: true,
          enableAssetLocation: true,
          enableAssetDates: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Export JSON v3 with dates and location'), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        home: AssetsPage(
          store: store,
          enableInventoryExportV3: true,
          enableAssetLocation: true,
          enableAssetDates: true,
          exportFiles: files,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export JSON v3 with dates and location'));
    await tester.pumpAndSettle();
    expect(find.text('Export inventory v3'), findsOneWidget);
    expect(find.textContaining('No v3 import or restore'), findsOneWidget);
    expect(store.exports, 0);
    await tester.tap(find.text('Prepare JSON'));
    await tester.pumpAndSettle();
    expect(store.exports, 1);
  });

  for (final delayed in [false, true]) {
    testWidgets(
      'real app sign-out removes v3 snapshot and pending result, delayed=$delayed',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final session = V3Session(snapshot);
        if (delayed) session.pending = Completer<AssetExportV3>();
        await tester.pumpWidget(
          AssetDeskApp(
            session: session,
            enableInventoryExportV3: true,
            enableAssetLocation: true,
            enableAssetDates: true,
          ),
        );
        await tester.pumpAndSettle();
        await login(tester);
        await tester.tap(find.text('Export JSON v3 with dates and location'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Prepare JSON'));
        if (delayed) {
          await tester.pump();
        } else {
          await tester.pumpAndSettle();
          expect(find.textContaining('Complete snapshot:'), findsOneWidget);
        }
        await tester.tap(find.text('Sign out'));
        await tester.pumpAndSettle();
        session.pending?.complete(snapshot);
        await tester.pumpAndSettle();
        expect(find.text('Export inventory v3'), findsNothing);
        expect(find.textContaining('Complete snapshot:'), findsNothing);
        expect(find.text('Save JSON as... (Windows)'), findsNothing);
        expect(session.account, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('explicit prepare, cancel retains snapshot, save succeeds', (
    tester,
  ) async {
    final source = ExportSource(snapshot);
    final files = ExportFiles();
    await open(tester, source, files);
    expect(source.calls, 0);
    expect(find.text('Save JSON as... (Windows)'), findsNothing);
    await tester.tap(find.text('Prepare JSON'));
    await tester.pumpAndSettle();
    expect(source.calls, 1);
    expect(files.saves, 0);
    expect(find.textContaining('Checksum matches'), findsOneWidget);
    await tester.tap(find.text('Save JSON as... (Windows)'));
    await tester.pumpAndSettle();
    expect(
      find.text('Save cancelled. Prepared snapshot retained.'),
      findsOneWidget,
    );
    expect(find.textContaining('Complete snapshot:'), findsOneWidget);
    files.saved = true;
    await tester.tap(find.text('Save JSON as... (Windows)'));
    await tester.pumpAndSettle();
    expect(files.saves, 2);
    expect(source.calls, 1);
    expect(find.text('Inventory JSON saved.'), findsOneWidget);
  });
  testWidgets(
    'save error retains snapshot without retry; prepare error clears stale snapshot',
    (tester) async {
      final source = ExportSource(snapshot);
      final files = ExportFiles()..error = const AssetFailure('File exists');
      await open(tester, source, files);
      await tester.tap(find.text('Prepare JSON'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save JSON as... (Windows)'));
      await tester.pumpAndSettle();
      expect(files.saves, 1);
      expect(find.text('File exists'), findsOneWidget);
      expect(find.textContaining('Complete snapshot:'), findsOneWidget);
      source.error = const AssetFailure('Export exceeds limit');
      await tester.tap(find.text('Prepare JSON'));
      await tester.pumpAndSettle();
      expect(find.text('Export exceeds limit'), findsOneWidget);
      expect(find.text('Save JSON as... (Windows)'), findsNothing);
    },
  );
  testWidgets('dispose rejects late prepare UI result', (tester) async {
    final source = ExportSource(snapshot)..pending = Completer<AssetExportV3>();
    await open(tester, source, ExportFiles());
    await tester.tap(find.text('Prepare JSON'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: Text('Signed out')));
    source.pending!.complete(snapshot);
    await tester.pumpAndSettle();
    expect(find.textContaining('Complete snapshot:'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('v3 export render $width at 200 percent', (tester) async {
      final font = Platform.environment['ASSET_DESK_UI_CAPTURE_FONT'];
      if (font != null) {
        final loader = FontLoader('Capture')
          ..addFont(
            Future.value(ByteData.sublistView(File(font).readAsBytesSync())),
          );
        await loader.load();
      }
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: font == null ? null : 'Capture'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: key,
            child: InventoryExportPage.v3(
              source: ExportSource(snapshot),
              files: ExportFiles(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prepare JSON'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Save JSON as... (Windows)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final directory = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
      if (directory != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$directory/export-v3-${width.toInt()}-200.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}

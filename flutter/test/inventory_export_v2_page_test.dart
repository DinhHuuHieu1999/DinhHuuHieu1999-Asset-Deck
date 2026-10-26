import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:asset_desk/api/asset_export.dart';
import 'package:asset_desk/api/asset_export_v2.dart';

import 'asset_export_v2_test.dart' show exportV2Fixture;
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

class ExportSource implements AssetExportV2Source {
  ExportSource(this.snapshot);
  final AssetExportV2 snapshot;
  int calls = 0;
  AssetFailure? error;
  Completer<AssetExportV2>? pending;
  @override
  Future<AssetExportV2> exportInventoryV2({
    required AssetExportDigest digest,
  }) async {
    calls++;
    if (error != null) throw error!;
    return pending == null ? snapshot : pending!.future;
  }
}

class ExportFiles implements InventoryExportFiles, InventoryExportV2Files {
  int saves = 0;
  bool saved = false;
  AssetFailure? error;
  @override
  Future<String> digest(Uint8List bytes) async => throw UnimplementedError();
  @override
  Future<bool> save(AssetExport snapshot) =>
      throw StateError('v1 must not run');
  @override
  Future<bool> saveV2(AssetExportV2 snapshot) async {
    saves++;
    if (error != null) throw error!;
    return saved;
  }
}

class V2Inventory extends FakeStore implements AssetExportV2Source {
  V2Inventory(this.snapshot);
  final AssetExportV2 snapshot;
  int exports = 0;
  @override
  Future<AssetExportV2> exportInventoryV2({
    required AssetExportDigest digest,
  }) async {
    exports++;
    return snapshot;
  }
}

class V2Session extends FakeSession implements AssetExportV2Source {
  V2Session(this.snapshot);
  final AssetExportV2 snapshot;
  Completer<AssetExportV2>? pending;
  @override
  Future<AssetExportV2> exportInventoryV2({
    required AssetExportDigest digest,
  }) async => pending?.future ?? snapshot;
}

void main() {
  late AssetExportV2 snapshot;
  setUpAll(() async {
    snapshot = await AssetExportV2.parse(
      exportV2Fixture(),
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
        home: InventoryExportPage.v2(source: source, files: files),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'v2 navigation requires both dates opt-in and source capability',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = V2Inventory(snapshot);
      final files = ExportFiles();
      await tester.pumpWidget(
        MaterialApp(
          home: AssetsPage(store: store, exportFiles: files),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Export JSON v2 with dates'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: AssetsPage(store: FakeStore(), enableAssetDates: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Export JSON v2 with dates'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: AssetsPage(
            store: store,
            enableAssetDates: true,
            exportFiles: files,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export JSON v2 with dates'));
      await tester.pumpAndSettle();
      expect(find.text('Export inventory v2'), findsOneWidget);
      expect(find.textContaining('No v2 import or restore'), findsOneWidget);
      expect(store.exports, 0);
      await tester.tap(find.text('Prepare JSON'));
      await tester.pumpAndSettle();
      expect(store.exports, 1);
    },
  );

  for (final delayed in [false, true]) {
    testWidgets(
      'real app sign-out removes v2 snapshot and pending result, delayed=$delayed',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final session = V2Session(snapshot);
        if (delayed) session.pending = Completer<AssetExportV2>();
        await tester.pumpWidget(
          AssetDeskApp(session: session, enableAssetDates: true),
        );
        await tester.pumpAndSettle();
        await login(tester);
        await tester.tap(find.text('Export JSON v2 with dates'));
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
        expect(find.text('Export inventory v2'), findsNothing);
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
    final source = ExportSource(snapshot)..pending = Completer<AssetExportV2>();
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
    testWidgets('v2 export render $width at 200 percent', (tester) async {
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
            child: InventoryExportPage.v2(
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
          final file = File('$directory/export-v2-${width.toInt()}-200.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:asset_desk/api/asset_session.dart';
import 'package:asset_desk/asset_desk_app.dart';
import 'package:asset_desk/assets_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'assets_page_test.dart' show FakeStore;
import 'asset_desk_app_test.dart' show FakeSession;
import 'inventory_selection_inspection_page_test.dart' show SelectionFiles;
import 'asset_selection_export_test.dart' show selectionFixture;

void main() {
  Future<void> size(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'inspection does not reload inventory or write; filters survive Back',
    (tester) async {
      await size(tester);
      final store = FakeStore();
      await tester.pumpWidget(
        MaterialApp(
          home: AssetsPage(
            store: store,
            inspectionFiles: SelectionFiles(),
            enableSelectionExport: true,
            enableAssetDates: true,
            enableAssetLocation: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '%_');
      await tester.enterText(
        find.widgetWithText(TextField, 'Category filter'),
        'network',
      );
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      final calls = List<String>.of(store.calls);
      await tester.tap(find.text('Inspect selection JSON (no import)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose JSON file (Windows)'));
      await tester.pumpAndSettle();
      expect(find.text('Checksum matches'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(store.calls, calls);
      expect(store.writes, 0);
      expect(
        find.text('Applied search: %_; status: all; category: network'),
        findsOneWidget,
      );
    },
  );
  for (final flags in [
    (false, true, true),
    (true, false, true),
    (true, true, false),
  ]) {
    testWidgets(
      'selection inspection requires all feature prerequisites: $flags',
      (tester) async {
        await size(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: AssetsPage(
              store: FakeStore(),
              enableSelectionExport: flags.$1,
              enableAssetDates: flags.$2,
              enableAssetLocation: flags.$3,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Inspect selection JSON (no import)'), findsNothing);
        expect(find.text('Inspect local JSON (no import)'), findsOneWidget);
      },
    );
  }
  for (final delayed in [false, true]) {
    testWidgets('real app sign-out removes inspection, delayed=$delayed', (
      tester,
    ) async {
      await size(tester);
      final bytes = Uint8List.fromList(
        utf8.encode(jsonEncode(selectionFixture())),
      );
      final envelope = jsonDecode(utf8.decode(bytes)) as Map;
      final pending = Completer<String>();
      const channel = MethodChannel('asset_desk/inventory_export');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'chooseInspectionJson') return bytes;
        if (call.method == 'sha256')
          return delayed ? pending.future : envelope['sha256'];
        throw StateError('Unexpected native method');
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final session = FakeSession()
        ..account = const AssetAccount(id: 'synthetic-owner', name: 'Owner');
      await tester.pumpWidget(
        AssetDeskApp(
          session: session,
          enableSelectionExport: true,
          enableAssetDates: true,
          enableAssetLocation: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inspect selection JSON (no import)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose JSON file (Windows)'));
      if (delayed) {
        await tester.pump();
      } else {
        await tester.pumpAndSettle();
        expect(find.text('Checksum matches'), findsOneWidget);
      }
      session.signOut();
      await tester.pumpAndSettle();
      if (delayed) pending.complete(envelope['sha256'] as String);
      await tester.pumpAndSettle();
      expect(find.text('Checksum matches'), findsNothing);
      expect(find.text('Choose JSON file (Windows)'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('selection inspection navigation at width $width and text 200%', (
      tester,
    ) async {
      final font = Platform.environment['ASSET_DESK_UI_CAPTURE_FONT'];
      if (font != null) {
        final loader = FontLoader('Capture');
        loader.addFont(
          Future.value(ByteData.sublistView(File(font).readAsBytesSync())),
        );
        await loader.load();
      }
      tester.view.physicalSize = Size(width, 1000);
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
            child: AssetsPage(
              store: FakeStore(),
              enableSelectionExport: true,
              enableAssetDates: true,
              enableAssetLocation: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
      if (directory != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '$directory/selection-inspection-navigation-${width.toInt()}-200.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}

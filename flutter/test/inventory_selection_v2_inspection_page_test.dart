import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/inventory_inspection_page.dart';
import 'package:asset_desk/inventory_inspection_files.dart';

import 'asset_selection_export_v2_test.dart' show selectionV2Fixture;

class SelectionFiles implements InventoryInspectionFiles {
  Uint8List? bytes = Uint8List.fromList(
    utf8.encode(jsonEncode(selectionV2Fixture(date: '2024-02-29'))),
  );
  Completer<String>? pending;
  bool failRead = false;
  int reads = 0;
  @override
  Future<Uint8List?> choose() async {
    reads++;
    if (failRead) throw StateError('private/path.json');
    return bytes;
  }

  @override
  Future<String> digest(Uint8List bytes) async =>
      pending == null ? 'a' * 64 : pending!.future;
}

void main() {
  testWidgets(
    'selection preview shows location/dates, cancel keeps preview, invalid selection clears it',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final files = SelectionFiles();
      await tester.pumpWidget(
        MaterialApp(home: InventoryInspectionPage.selectionV2(files: files)),
      );
      Future<void> choose() async {
        await tester.tap(find.text('Choose JSON file (Windows)'));
        await tester.pumpAndSettle();
      }

      await choose();
      expect(find.text('Checksum matches'), findsOneWidget);
      expect(find.text('Last checked: 2024-02-29'), findsOneWidget);
      expect(find.text('Location: Room %_1'), findsOneWidget);
      expect(find.text('Purchased: 2024-02-29'), findsOneWidget);
      expect(find.text('Warranty expires: 2026-10-26'), findsOneWidget);
      await tester.tap(find.text('File filters'));
      await tester.pumpAndSettle();
      expect(find.text('locationMode'), findsOneWidget);
      expect(find.text('exact'), findsOneWidget);
      expect(find.text('%_'), findsOneWidget);
      expect(find.text('name_asc'), findsOneWidget);
      expect(find.textContaining('Confirm new records'), findsNothing);
      files.bytes = null;
      await choose();
      expect(find.text('Location: Room %_1'), findsOneWidget);
      expect(find.textContaining('Previous preview retained'), findsOneWidget);
      expect(find.text('Checksum matches'), findsOneWidget);
      files.bytes = Uint8List.fromList(utf8.encode('{}'));
      await choose();
      expect(find.text('Location: Room %_1'), findsNothing);
      expect(find.textContaining('Unable to inspect JSON'), findsOneWidget);
    },
  );
  testWidgets(
    'new verification clears old evidence and blocks repeated choose',
    (tester) async {
      final files = SelectionFiles();
      await tester.pumpWidget(
        MaterialApp(home: InventoryInspectionPage.selectionV2(files: files)),
      );
      await tester.tap(find.text('Choose JSON file (Windows)'));
      await tester.pumpAndSettle();
      expect(find.text('Checksum matches'), findsOneWidget);
      files.pending = Completer<String>();
      await tester.tap(find.text('Choose JSON file (Windows)'));
      await tester.pump();
      expect(find.text('Checksum matches'), findsNothing);
      expect(find.text('File filters'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Choose JSON file (Windows)'),
      );
      expect(button.onPressed, isNull);
      expect(files.reads, 2);
      files.pending!.complete('0' * 64);
      await tester.pumpAndSettle();
      expect(find.textContaining('Unable to inspect JSON'), findsOneWidget);
      expect(find.text('Checksum matches'), findsNothing);
    },
  );

  testWidgets(
    'read failures clear preview without exposing paths or retrying',
    (tester) async {
      final files = SelectionFiles();
      await tester.pumpWidget(
        MaterialApp(home: InventoryInspectionPage.selectionV2(files: files)),
      );
      await tester.tap(find.text('Choose JSON file (Windows)'));
      await tester.pumpAndSettle();
      files.failRead = true;
      await tester.tap(find.text('Choose JSON file (Windows)'));
      await tester.pumpAndSettle();
      expect(files.reads, 2);
      expect(find.text('Checksum matches'), findsNothing);
      expect(find.text('File filters'), findsNothing);
      expect(find.textContaining('private/path'), findsNothing);
      expect(find.textContaining('Unable to inspect JSON'), findsOneWidget);
    },
  );

  testWidgets(
    'empty selection is a verified zero count, not a failed preview',
    (tester) async {
      final files = SelectionFiles()
        ..bytes = Uint8List.fromList(
          utf8.encode(jsonEncode(selectionV2Fixture(count: 0))),
        );
      await tester.pumpWidget(
        MaterialApp(home: InventoryInspectionPage.selectionV2(files: files)),
      );
      await tester.tap(find.text('Choose JSON file (Windows)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Assets: 0;'), findsOneWidget);
      expect(find.text('Checksum matches'), findsOneWidget);
      expect(find.text('File filters'), findsOneWidget);
    },
  );

  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('inspection render $width at text 200%', (tester) async {
      final font = Platform.environment['ASSET_DESK_UI_CAPTURE_FONT'];
      if (font != null) {
        final loader = FontLoader('Capture');
        loader.addFont(
          Future.value(ByteData.sublistView(File(font).readAsBytesSync())),
        );
        await loader.load();
      }
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      final files = SelectionFiles();
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
            child: InventoryInspectionPage.selectionV2(files: files),
          ),
        ),
      );
      await tester.tap(find.text('Choose JSON file (Windows)'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Checksum matches'), findsOneWidget);
      files.bytes = null;
      await tester.tap(find.text('Choose JSON file (Windows)'));
      await tester.pumpAndSettle();
      expect(find.text('Checksum matches'), findsOneWidget);
      expect(find.textContaining('Previous preview retained'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
      if (directory != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '$directory/inspection-selection-cancel-${width.toInt()}-200.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}

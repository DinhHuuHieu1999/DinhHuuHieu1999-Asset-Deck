import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/inventory_inspection_page.dart';
import 'package:asset_desk/inventory_inspection_files.dart';

import 'asset_export_v3_test.dart' show exportV3Fixture;

class V3Files implements InventoryInspectionFiles {
  Uint8List? bytes = Uint8List.fromList(
    utf8.encode(jsonEncode(exportV3Fixture())),
  );
  @override
  Future<Uint8List?> choose() async => bytes;
  @override
  Future<String> digest(Uint8List bytes) async => 'a' * 64;
}

void main() {
  testWidgets(
    'v3 preview shows location/dates, cancel keeps preview, invalid selection clears it',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final files = V3Files();
      await tester.pumpWidget(
        MaterialApp(home: InventoryInspectionPage(files: files, v3: true)),
      );
      Future<void> choose() async {
        await tester.tap(find.text('Choose JSON file (Windows)'));
        await tester.pumpAndSettle();
      }

      await choose();
      expect(find.text('Checksum matches'), findsOneWidget);
      expect(find.text('Location: Room %_1'), findsOneWidget);
      expect(find.text('Purchased: 2024-02-29'), findsOneWidget);
      expect(find.text('Warranty expires: 2026-10-26'), findsOneWidget);
      files.bytes = null;
      await choose();
      expect(find.text('Location: Room %_1'), findsOneWidget);
      expect(find.textContaining('Previous preview retained'), findsOneWidget);
      files.bytes = Uint8List.fromList(utf8.encode('{}'));
      await choose();
      expect(find.text('Location: Room %_1'), findsNothing);
      expect(find.textContaining('Unable to inspect JSON'), findsOneWidget);
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
            child: InventoryInspectionPage(files: V3Files(), v3: true),
          ),
        ),
      );
      await tester.tap(find.text('Choose JSON file (Windows)'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Checksum matches'), findsOneWidget);
      final directory = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
      if (directory != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '$directory/inspection-v3-${width.toInt()}-200.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}

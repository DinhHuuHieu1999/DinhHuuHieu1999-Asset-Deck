import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/inventory_inspection_files.dart';
import 'package:asset_desk/inventory_inspection_page.dart';

class Files implements InventoryInspectionFiles {
  Uint8List? bytes = File('test/fixtures/inventory-export-v1.json')
      .readAsBytesSync();
  Completer<String>? pending;
  Completer<Uint8List?>? selection;
  bool readError = false;
  int reads = 0;
  int hashes = 0;
  @override
  Future<Uint8List?> choose() async {
    reads++;
    if (readError) throw StateError('private-file-path');
    return selection == null ? bytes : selection!.future;
  }

  @override
  Future<String> digest(Uint8List value) async {
    hashes++;
    return pending == null
        ? (jsonDecode(utf8.decode(bytes!)) as Map)['sha256'] as String
        : pending!.future;
  }
}

Future<void> choose(WidgetTester tester) async {
  await tester.tap(find.text('Choose JSON file (Windows)'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Cancel retains validated preview', (tester) async {
    final files = Files();
    await tester.pumpWidget(
      MaterialApp(home: InventoryInspectionPage(files: files)),
    );
    expect(find.text('Checksum matches'), findsNothing);
    await choose(tester);
    expect(find.text('Checksum matches'), findsOneWidget);
    files.bytes = null;
    await choose(tester);
    expect(find.textContaining('Previous preview retained'), findsOneWidget);
    expect(find.textContaining('Assets: 1'), findsOneWidget);
  });
  testWidgets('new selection clears preview before checksum failure', (
    tester,
  ) async {
    final files = Files();
    await tester.pumpWidget(
      MaterialApp(home: InventoryInspectionPage(files: files)),
    );
    await choose(tester);
    files.pending = Completer<String>();
    await tester.tap(find.text('Choose JSON file (Windows)'));
    await tester.pump();
    expect(find.textContaining('Assets: 1'), findsNothing);
    files.pending!.complete('0' * 64);
    await tester.pumpAndSettle();
    expect(find.textContaining('Unable to inspect JSON'), findsOneWidget);
    expect(find.text('Checksum matches'), findsNothing);
  });
  testWidgets('late digest after disposal cannot restore preview', (
    tester,
  ) async {
    final files = Files()..pending = Completer<String>();
    await tester.pumpWidget(
      MaterialApp(home: InventoryInspectionPage(files: files)),
    );
    await tester.tap(find.text('Choose JSON file (Windows)'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: Text('Signed out')));
    files.pending!.complete('0' * 64);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Signed out'), findsOneWidget);
  });
  testWidgets(
    'read error clears old preview without disclosing path or retrying',
    (tester) async {
      final files = Files();
      await tester.pumpWidget(
        MaterialApp(home: InventoryInspectionPage(files: files)),
      );
      await choose(tester);
      files.readError = true;
      await choose(tester);
      expect(find.textContaining('Assets: 1'), findsNothing);
      expect(find.textContaining('Unable to inspect JSON'), findsOneWidget);
      expect(find.textContaining('private-file-path'), findsNothing);
      expect(files.reads, 2);
      expect(files.hashes, 1);
    },
  );
  testWidgets('late picker after disposal never starts hashing', (
    tester,
  ) async {
    final files = Files()..selection = Completer<Uint8List?>();
    await tester.pumpWidget(
      MaterialApp(home: InventoryInspectionPage(files: files)),
    );
    await tester.tap(find.text('Choose JSON file (Windows)'));
    await tester.pump();
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Choose JSON file (Windows)'),
    );
    expect(button.onPressed, isNull);
    await tester.pumpWidget(const MaterialApp(home: Text('Signed out')));
    files.selection!.complete(files.bytes);
    await tester.pumpAndSettle();
    expect(files.reads, 1);
    expect(files.hashes, 0);
    expect(tester.takeException(), isNull);
  });
  for (final width in [390.0, 1440.0]) {
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
            child: InventoryInspectionPage(files: Files()),
          ),
        ),
      );
      await choose(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Checksum matches'), findsOneWidget);
      final directory = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
      if (directory != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$directory/inspection-${width.toInt()}-200.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:asset_desk/asset_desk_app.dart';
import 'package:asset_desk/api/asset_import.dart';
import 'package:asset_desk/api/asset_session.dart';
import 'package:asset_desk/assets_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'asset_desk_app_test.dart' show FakeSession;
import 'inventory_inspection_page_test.dart' show Files;

class ImportSession extends FakeSession implements AssetImportSource {
  int imports = 0;
  @override
  Future<AssetImportReceipt> importInventory(
    AssetImportDraft draft, {
    required int sessionRevision,
  }) async {
    imports++;
    throw StateError('not expected');
  }
}

void main() {
  for (final enabled in [false, true]) {
    testWidgets('inventory import navigation opt-in=$enabled', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = ImportSession()
        ..account = const AssetAccount(
          id: 'aaaaaaaaaaaaaaaaaaaaaaaa',
          name: 'Synthetic',
        );
      addTearDown(session.close);
      await tester.pumpWidget(
        MaterialApp(
          home: AssetsPage(
            store: session,
            inspectionFiles: Files(),
            enableInventoryImport: enabled,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final entry = find.text('Import inventory JSON (add only)');
      expect(entry, enabled ? findsOneWidget : findsNothing);
      expect(find.text('Inspect local JSON (no import)'), findsOneWidget);
      if (enabled) {
        await tester.tap(entry);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Choose import JSON (Windows)'));
        await tester.pumpAndSettle();
        expect(find.textContaining('New assets: 1'), findsOneWidget);
        expect(session.imports, 0);
      }
    });
  }
  testWidgets('real app sign-out removes import preview', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = ImportSession()
      ..account = const AssetAccount(
        id: 'aaaaaaaaaaaaaaaaaaaaaaaa',
        name: 'Synthetic',
      );
    final bytes = File('test/fixtures/inventory-export-v1.json')
        .readAsBytesSync();
    const channel = MethodChannel('asset_desk/inventory_export');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'chooseInspectionJson') return bytes;
      if (call.method == 'sha256')
        return (jsonDecode(utf8.decode(bytes))
            as Map<String, Object?>)['sha256'];
      throw StateError('Unexpected method');
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      AssetDeskApp(session: session, enableInventoryImport: true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import inventory JSON (add only)'));
    await tester.pumpAndSettle();
    expect(find.text('Choose import JSON (Windows)'), findsOneWidget);
    await tester.tap(find.text('Choose import JSON (Windows)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('New assets: 1'), findsOneWidget);
    session.signOut();
    await tester.pumpAndSettle();
    expect(find.text('Choose import JSON (Windows)'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(session.imports, 0);
  });
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('opt-in import navigation at width $width and text 200%', (
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
      final session = ImportSession()
        ..account = const AssetAccount(
          id: 'aaaaaaaaaaaaaaaaaaaaaaaa',
          name: 'Synthetic',
        );
      addTearDown(session.close);
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
            child: AssetsPage(store: session, enableInventoryImport: true),
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
          final file = File('$directory/navigation-${width.toInt()}-200.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}

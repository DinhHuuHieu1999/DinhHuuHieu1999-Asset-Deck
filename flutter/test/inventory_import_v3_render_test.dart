import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/assets_page.dart';
import 'package:asset_desk/inventory_import_v3_page.dart';
import 'package:asset_desk/api/asset_session.dart';

import 'inventory_import_v3_page_test.dart' as page;
import 'inventory_import_v3_navigation_test.dart' as navigation;

void main() {
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('v3 navigation and uncertain render $width at 200%', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final font = Platform.environment['ASSET_DESK_UI_CAPTURE_FONT'];
      if (font != null) {
        final loader = FontLoader('Capture');
        loader.addFont(
          Future.value(ByteData.sublistView(File(font).readAsBytesSync())),
        );
        await loader.load();
      }
      final key = GlobalKey();
      Future<void> mount(Widget child) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: font == null ? null : 'Capture'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: RepaintBoundary(key: key, child: child),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> capture(String state) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final directory = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
        if (directory == null) return;
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '$directory/import-v3-$state-${width.toInt()}-200.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      final nav = navigation.V3Session()
        ..account = const AssetAccount(
          id: 'aaaaaaaaaaaaaaaaaaaaaaaa',
          name: 'Synthetic',
        );
      addTearDown(nav.close);
      await mount(
        AssetsPage(
          store: nav,
          enableInventoryImportV3: true,
          enableInventoryImport: true,
          enableAssetDates: true,
          enableAssetLocation: true,
        ),
      );
      final entry = find.text(
        'Import inventory JSON v3 (add-only, dates and location)',
      );
      await tester.ensureVisible(entry);
      await capture('navigation');
      expect(nav.imports, 0);
      await tester.pumpWidget(const SizedBox());
      final session = page.Session();
      addTearDown(session.changes.close);
      final source = page.Source()..fail = true;
      await mount(
        InventoryImportV3Page(
          apiBase: 'https://localhost/api/v1',
          session: session,
          source: source,
          files: page.Files(),
          recoveryFiles: page.RecoveryFiles(),
        ),
      );
      await tester.tap(find.text('Choose import JSON (Windows)'));
      await tester.pumpAndSettle();
      await page.saveRecovery(tester);
      await tester.scrollUntilVisible(
        find.byType(Checkbox),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      final confirm = find.text('Confirm new records');
      await tester.scrollUntilVisible(
        confirm,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      final message = find.textContaining('Outcome not confirmed.');
      await tester.scrollUntilVisible(
        message,
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await capture('uncertain');
      expect(source.calls, 1);
      final replay = find.text('Replay same operation');
      await tester.scrollUntilVisible(
        replay,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await capture('replay');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Replay same operation'),
            )
            .onPressed,
        isNull,
      );
    });
  }
}

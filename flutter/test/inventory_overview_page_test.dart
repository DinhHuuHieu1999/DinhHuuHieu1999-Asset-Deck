import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:asset_desk/api/asset_overview.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:asset_desk/assets_page.dart';
import 'package:asset_desk/inventory_overview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'asset_overview_test.dart' show summary;
import 'assets_page_test.dart' show FakeStore;

class OverviewStore extends FakeStore implements AssetOverviewSource {
  int reads = 0;
  Future<AssetOverview> Function()? load;
  @override
  Future<AssetOverview> overview() async {
    reads++;
    return load == null ? AssetOverview.fromJson(summary()) : await load!();
  }
}

void main() {
  testWidgets(
    'explicit navigation preserves unapplied list draft without writes',
    (tester) async {
      final store = OverviewStore();
      await tester.pumpWidget(MaterialApp(home: AssetsPage(store: store)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'draft');
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Inventory overview'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Total assets: 53'), findsOneWidget);
      expect(store.reads, 1);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('draft'), findsOneWidget);
      expect(store.writes, 0);
      expect(store.calls.length, 1);
    },
  );
  testWidgets(
    'refresh failure keeps counts with stale warning; retry succeeds',
    (tester) async {
      final store = OverviewStore();
      await tester.pumpWidget(
        MaterialApp(home: InventoryOverviewPage(source: store)),
      );
      await tester.pumpAndSettle();
      store.load = () async =>
          throw const AssetFailure('Overview unavailable', statusCode: 422);
      await tester.tap(find.text('Refresh overview'));
      await tester.pumpAndSettle();
      expect(find.text('Total assets: 53'), findsOneWidget);
      expect(find.textContaining('last successful load'), findsOneWidget);
      expect(find.text('Overview unavailable'), findsOneWidget);
      store.load = null;
      await tester.tap(find.text('Refresh overview'));
      await tester.pumpAndSettle();
      expect(find.textContaining('last successful load'), findsNothing);
      expect(store.reads, 3);
    },
  );
  testWidgets('initial failure never displays zero inventory', (tester) async {
    final store = OverviewStore()
      ..load = (() async =>
          throw const AssetFailure('Please sign in again', statusCode: 401));
    await tester.pumpWidget(
      MaterialApp(home: InventoryOverviewPage(source: store)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Please sign in again'), findsOneWidget);
    expect(find.textContaining('Total assets:'), findsNothing);
  });
  testWidgets('source replacement discards old pending response', (
    tester,
  ) async {
    final pending = Completer<AssetOverview>();
    final old = OverviewStore()..load = (() => pending.future);
    final next = OverviewStore();
    await tester.pumpWidget(
      MaterialApp(home: InventoryOverviewPage(source: old)),
    );
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(home: InventoryOverviewPage(source: next)),
    );
    await tester.pumpAndSettle();
    pending.completeError(const AssetFailure('Old account error'));
    await tester.pumpAndSettle();
    expect(find.text('Total assets: 53'), findsOneWidget);
    expect(find.text('Old account error'), findsNothing);
  });
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('synthetic overview $width at text 200%', (tester) async {
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
            child: InventoryOverviewPage(source: OverviewStore()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Total assets: 53'), findsOneWidget);
      final dir = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
      if (dir != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$dir/overview-${width.toInt()}-200.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}

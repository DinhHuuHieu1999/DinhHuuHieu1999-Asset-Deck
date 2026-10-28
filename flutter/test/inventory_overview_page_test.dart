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
import 'asset_desk_app_test.dart' show FakeSession;
import 'asset_test.dart' show record;

import 'package:asset_desk/api/asset.dart';

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

class OverviewSession extends FakeSession implements AssetOverviewSource {
  final pending = Completer<AssetOverview>();
  @override
  Future<AssetOverview> overview() => pending.future;
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
  test('selection validates fixed status and exact category without wildcard interpretation', () {
    expect(InventoryOverviewSelection.status('repair').status, 'repair');
    final astral = String.fromCharCode(0x1f527) * 64;
    expect(InventoryOverviewSelection.category(astral).category, astral);
    expect(
      () => InventoryOverviewSelection.category(astral + 'x'),
      throwsFormatException,
    );
    expect(InventoryOverviewSelection.category('%_ room').category, '%_ room');
    for (final status in ['', 'unknown', 'STORED']) {
      expect(
        () => InventoryOverviewSelection.status(status),
        throwsFormatException,
      );
    }
    for (final category in ['', ' trailing ', 'x' * 65, 'bad\u0000']) {
      expect(
        () => InventoryOverviewSelection.category(category),
        throwsFormatException,
      );
    }
  });
  testWidgets('status selection clears other filters and loads page one', (
    tester,
  ) async {
    final store = OverviewStore();
    await tester.pumpWidget(MaterialApp(home: AssetsPage(store: store)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'draft');
    await tester.tap(find.text('Inventory overview'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('View assets: repair'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('View assets: repair'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Applied search:'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(store.calls.last, '|repair|0');
    expect(store.categories.last, '');
    expect(store.writes, 0);
    expect(
      find.textContaining(
        'Applied search: (none); status: repair; category: all',
      ),
      findsOneWidget,
    );
  });
  testWidgets(
    'failed category drilldown retains old results and filter identity',
    (tester) async {
      final store = OverviewStore();
      await tester.pumpWidget(MaterialApp(home: AssetsPage(store: store)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'old');
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inventory overview'));
      await tester.pumpAndSettle();
      store.failure = const AssetFailure('Synthetic list failure');
      await tester.scrollUntilVisible(
        find.text('View assets: network'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('View assets: network'));
      await tester.pumpAndSettle();
      expect(store.categories.last, 'network');
      await tester.scrollUntilVisible(
        find.text('Laptop'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Laptop'), findsOneWidget);
      expect(find.textContaining('Applied search: old;'), findsOneWidget);
      expect(find.textContaining('may be stale'), findsOneWidget);
      expect(store.writes, 0);
    },
  );
  testWidgets('session change clears counts and rejects a late overview', (
    tester,
  ) async {
    final session = OverviewSession();
    await tester.pumpWidget(
      MaterialApp(home: InventoryOverviewPage(source: session)),
    );
    await tester.pump();
    session.signOut();
    await tester.pump();
    session.pending.complete(AssetOverview.fromJson(summary()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Session changed'), findsOneWidget);
    expect(find.textContaining('Total assets:'), findsNothing);
    expect(find.text('View assets: stored'), findsNothing);
    session.close();
  });
  testWidgets('literal category selection is retained on the next page', (
    tester,
  ) async {
    final store = OverviewStore();
    store.load = () async => AssetOverview.fromJson({
      ...summary(),
      'byCategory': [
        {'category': '%_ room', 'count': 53},
      ],
    });
    store.pages = {
      0: AssetPage(
        List.generate(50, (i) => AssetRecord.fromJson(record(i))),
        50,
      ),
      50: AssetPage([AssetRecord.fromJson(record(50))], null),
    };
    await tester.pumpWidget(MaterialApp(home: AssetsPage(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inventory overview'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('View assets: %_ room'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('View assets: %_ room'));
    await tester.pumpAndSettle();
    expect(store.calls.last, '||0');
    expect(store.categories.last, '%_ room');
    await tester.scrollUntilVisible(
      find.text('Next page'),
      1500,
      maxScrolls: 80,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Next page'));
    await tester.pumpAndSettle();
    expect(store.calls.last, '||50');
    expect(store.categories.last, '%_ room');
    expect(store.writes, 0);
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

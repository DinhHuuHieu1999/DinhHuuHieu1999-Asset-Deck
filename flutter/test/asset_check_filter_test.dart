import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:asset_desk/api/asset_selection_export.dart';
import 'package:asset_desk/api/asset_check.dart';
import 'package:asset_desk/assets_page.dart';

import 'assets_page_test.dart' show FakeStore;

class CheckStore extends FakeStore
    implements AssetCheckSource, AssetCheckBeforeSource {
  final beforeCalls = <String>[];
  @override
  Future<AssetCheckPage> listCheckedBefore({
    required String checkBefore,
    required String query,
    required String status,
    required int offset,
    String sort = 'updated_desc',
    String category = '',
    bool includeLocation = false,
    String locationMode = 'all',
    String? location,
    String warranty = '',
    String asOf = '',
  }) async {
    beforeCalls.add(checkBefore);
    if (failure != null) throw failure!;
    return AssetCheckPage(AssetPage([], null));
  }

  int uncheckedCalls = 0;
  @override
  Future<AssetCheckPage> listUnchecked({
    required String query,
    required String status,
    required int offset,
    String sort = 'updated_desc',
    String category = '',
    bool includeLocation = false,
    String locationMode = 'all',
    String? location,
    String warranty = '',
    String asOf = '',
  }) async {
    uncheckedCalls++;
    if (failure != null) throw failure!;
    return AssetCheckPage(AssetPage([], null));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected operation');
}

class CheckExportStore extends CheckStore
    implements AssetSelectionExportSource {}

void main() {
  testWidgets(
    'before date validates, applies explicitly and refresh retains applied cutoff',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = CheckStore();
      await tester.pumpWidget(
        MaterialApp(home: AssetsPage(store: store, enableAssetCheck: true)),
      );
      await tester.pumpAndSettle();
      Future<void> press(String label) async {
        await tester.scrollUntilVisible(
          find.text(label),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      await press('Checked before');
      await press('Apply filters');
      expect(find.text('Enter a real date as YYYY-MM-DD.'), findsOneWidget);
      expect(store.beforeCalls, isEmpty);
      await tester.enterText(
        find.widgetWithText(TextField, 'Before date'),
        '2024-02-29',
      );
      await press('Apply filters');
      expect(store.beforeCalls, ['2024-02-29']);
      expect(
        find.text('Applied check filter: Before 2024-02-29'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Before date'),
        '2025-01-01',
      );
      await press('Refresh inventory');
      expect(store.beforeCalls, ['2024-02-29', '2024-02-29']);
      await press('Reset filters');
      expect(find.text('Applied check filter: All assets'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Before date'), findsNothing);
    },
  );

  for (final before in [false, true]) {
    testWidgets(
      'matching export respects applied check filter (before: $before)',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: AssetsPage(
              store: CheckExportStore(),
              enableAssetCheck: true,
              enableSelectionExport: true,
              enableAssetDates: true,
              enableAssetLocation: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final export = find.widgetWithText(
          OutlinedButton,
          'Export matching assets JSON',
        );
        expect(tester.widget<OutlinedButton>(export).onPressed, isNotNull);
        Future<void> press(String text) async {
          await tester.scrollUntilVisible(
            find.text(text),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text(text));
          await tester.pumpAndSettle();
        }

        await press(before ? 'Checked before' : 'Only unknown check dates');
        if (before) {
          await tester.enterText(
            find.widgetWithText(TextField, 'Before date'),
            '2024-02-29',
          );
        }
        await press('Apply filters');
        await tester.scrollUntilVisible(
          find.text('Export matching assets JSON'),
          -250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.widget<OutlinedButton>(export).onPressed, isNull);
        expect(
          find.textContaining('Matching export is unavailable'),
          findsOneWidget,
        );
        await press('Reset filters');
        await tester.scrollUntilVisible(
          find.text('Export matching assets JSON'),
          -250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.widget<OutlinedButton>(export).onPressed, isNotNull);
      },
    );
    testWidgets(
      'failed apply preserves old page and check mode (before: $before)',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = CheckStore();
        await tester.pumpWidget(
          MaterialApp(home: AssetsPage(store: store, enableAssetCheck: true)),
        );
        await tester.pumpAndSettle();
        Future<void> press(String text) async {
          await tester.ensureVisible(find.text(text));
          await tester.tap(find.text(text));
          await tester.pumpAndSettle();
        }

        await press(before ? 'Checked before' : 'Only unknown check dates');
        if (before) {
          await tester.enterText(
            find.widgetWithText(TextField, 'Before date'),
            '2024-02-29',
          );
        }
        store.failure = const AssetFailure('Synthetic filter unavailable');
        await press('Apply filters');
        expect(before ? store.beforeCalls.length : store.uncheckedCalls, 1);
        expect(find.text('Applied check filter: All assets'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Laptop'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Laptop'), findsOneWidget);
        store.failure = null;
        await press('Refresh inventory');
        expect(before ? store.beforeCalls.length : store.uncheckedCalls, 1);
        expect(find.text('Applied check filter: All assets'), findsOneWidget);
      },
    );
  }
  testWidgets('disabled feature exposes no check filter or reads', (
    tester,
  ) async {
    final store = CheckStore();
    await tester.pumpWidget(MaterialApp(home: AssetsPage(store: store)));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(store.uncheckedCalls, 0);
  });
  testWidgets(
    'unchecked applies explicitly, refresh retains it and reset clears it',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = CheckStore();
      await tester.pumpWidget(
        MaterialApp(home: AssetsPage(store: store, enableAssetCheck: true)),
      );
      await tester.pumpAndSettle();
      Future<void> press(String label) async {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      await press('Only unknown check dates');
      expect(store.uncheckedCalls, 0);
      await press('Refresh inventory');
      expect(store.uncheckedCalls, 0);
      await press('Apply filters');
      expect(store.uncheckedCalls, 1);
      expect(find.text('Applied check filter: Unknown date'), findsOneWidget);
      await press('Only unknown check dates');
      await press('Refresh inventory');
      expect(store.uncheckedCalls, 2);
      await press('Reset filters');
      expect(store.uncheckedCalls, 2);
      expect(find.text('Applied check filter: All assets'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Only unknown check dates'),
            )
            .value,
        false,
      );
    },
  );
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('unchecked inventory reflows at $width and 200 percent', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final font = Platform.environment['ASSET_DESK_UI_CAPTURE_FONT'];
      if (font != null) {
        final loader = FontLoader('Capture')
          ..addFont(
            Future.value(ByteData.sublistView(File(font).readAsBytesSync())),
          );
        await loader.load();
      }
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
            child: AssetsPage(store: CheckStore(), enableAssetCheck: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Checked before'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Checked before'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
      if (directory != null)
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '$directory/unchecked-inventory-${width.toInt()}-200.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
    });
  }
}

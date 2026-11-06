import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/assets_page.dart';
import 'package:asset_desk/api/asset_sort.dart';
import 'package:asset_desk/api/asset_check.dart';
import 'package:asset_desk/api/asset_overview.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:asset_desk/api/asset_location.dart';
import 'package:asset_desk/api/asset_selection_export.dart';
import 'package:asset_desk/api/asset_selection_export_v2.dart';

import 'asset_check_filter_test.dart' show CheckExportStore;

class CheckSortStore extends CheckExportStore implements AssetOverviewSource {
  @override
  Future<AssetCheck> readCheckDate(String id) async =>
      AssetCheck(id: id, version: 1, lastCheckedOn: null);
  @override
  Future<AssetOverview> overview() async => AssetOverview.fromJson({
    'complete': true,
    'total': 1,
    'byStatus': {'in_use': 1, 'stored': 0, 'repair': 0, 'retired': 0},
    'byCategory': [
      {'category': 'Computers', 'count': 1},
    ],
  });
}

class SortSelectionStore extends CheckExportStore
    implements AssetLocationSource, AssetSelectionExportV2Source {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #listLocations) {
      sorts.add(invocation.namedArguments[#sort] as String? ?? 'updated_desc');
      if (failure != null) return Future<AssetLocationPage>.error(failure!);
      return Future.value(AssetLocationPage([], null));
    }
    return super.noSuchMethod(invocation);
  }
}

Future<void> chooseSort(
  WidgetTester tester,
  String current,
  String label,
) async {
  final finder = find.byKey(ValueKey('inventory-sort-$current'));
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(finder);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> press(WidgetTester tester, String label) async {
  final finder = find.text(label);
  // ensureVisible also scrolls backwards when controls precede the current view.
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('list extension never widens selection JSON sort enums', () {
    expect(assetSorts, ['updated_desc', 'name_asc']);
    expect(assetListSorts, contains('checked_asc'));
    final scope = <String, Object?>{
      'q': '',
      'status': '',
      'category': '',
      'locationMode': 'all',
      'location': null,
      'sort': 'checked_asc',
      'warranty': null,
    };
    expect(() => AssetSelectionScope.fromJson(scope), throwsFormatException);
    expect(
      () => AssetSelectionScopeV2.fromJson({
        ...scope,
        'check': {'mode': 'all'},
      }),
      throwsFormatException,
    );
  });

  testWidgets('check sort is absent when capability disabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AssetsPage(store: CheckExportStore())),
    );
    await tester.pumpAndSettle();
    await chooseSort(tester, 'updated_desc', 'Name A-Z');
    expect(find.text('Oldest check date (Unknown last)'), findsNothing);
  });

  testWidgets(
    'Apply, failed draft, Refresh and Reset keep applied check sort',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = CheckSortStore();
      await tester.pumpWidget(
        MaterialApp(home: AssetsPage(store: store, enableAssetCheck: true)),
      );
      await tester.pumpAndSettle();
      await chooseSort(
        tester,
        'updated_desc',
        'Oldest check date (Unknown last)',
      );
      expect(store.sorts, ['updated_desc']);
      await press(tester, 'Refresh inventory');
      expect(store.sorts.last, 'updated_desc');
      await press(tester, 'Apply filters');
      expect(store.sorts.last, 'checked_asc');
      final requestsBeforeBack = store.sorts.length;
      await press(tester, 'View details');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(store.sorts.length, requestsBeforeBack);
      await press(tester, 'Inventory overview');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(store.sorts.length, requestsBeforeBack);
      await press(tester, 'Inventory overview');
      await press(tester, 'View assets: in_use');
      expect(store.sorts.last, 'checked_asc');
      await chooseSort(tester, 'checked_asc', 'Name A-Z');
      store.failure = const AssetFailure('Synthetic failed load');
      await press(tester, 'Apply filters');
      expect(
        find.text('Applied sort: Oldest check date (Unknown last)'),
        findsOneWidget,
      );
      expect(find.text('Laptop'), findsOneWidget);
      store.failure = null;
      await press(tester, 'Refresh inventory');
      expect(store.sorts.last, 'checked_asc');
      await press(tester, 'Reset filters');
      expect(store.sorts.last, 'checked_asc');
      expect(store.writes, 0);
    },
  );

  testWidgets(
    'both selection export versions disable only after new sort applies',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = SortSelectionStore();
      await tester.pumpWidget(
        MaterialApp(
          home: AssetsPage(
            store: store,
            enableAssetCheck: true,
            enableAssetDates: true,
            enableAssetLocation: true,
            enableSelectionExport: true,
            enableSelectionExportV2: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final exports = [
        'Export matching assets JSON',
        'Export matching assets JSON v2 with check dates',
      ];
      Future<void> assertButtons(bool enabled) async {
        for (final label in exports) {
          final finder = find.widgetWithText(OutlinedButton, label);
          if (finder.evaluate().isEmpty)
            await tester.scrollUntilVisible(
              find.text(label),
              -250,
              scrollable: find.byType(Scrollable).first,
            );
          expect(
            tester.widget<OutlinedButton>(finder).onPressed,
            enabled ? isNotNull : isNull,
          );
        }
      }

      await assertButtons(true);
      await chooseSort(
        tester,
        'updated_desc',
        'Oldest check date (Unknown last)',
      );
      await assertButtons(true);
      await press(tester, 'Apply filters');
      await assertButtons(false);
      expect(
        find.textContaining('Matching JSON export does not support'),
        findsOneWidget,
      );
      await chooseSort(tester, 'checked_asc', 'Name A-Z');
      await press(tester, 'Apply filters');
      await assertButtons(true);
      expect(store.writes, 0);
    },
  );

  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('check sort render $width at 200%', (tester) async {
      tester.view.physicalSize = Size(width, 1400);
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
            child: AssetsPage(
              store: CheckExportStore(),
              enableAssetCheck: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await chooseSort(
        tester,
        'updated_desc',
        'Oldest check date (Unknown last)',
      );
      expect(tester.takeException(), isNull);
      final dir = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
      if (dir != null)
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$dir/check-sort-${width.toInt()}-200.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
    });
  }
}

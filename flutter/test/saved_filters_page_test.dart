import 'package:asset_desk/api/asset_warranty.dart';
import 'package:asset_desk/api/asset_store.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:asset_desk/assets_page.dart';

import 'assets_page_test.dart' show FakeStore;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset_saved_filter.dart';
import 'package:asset_desk/saved_filters_page.dart';

class FakeSavedSource implements AssetSavedFilterSource {
  int lists = 0;
  bool fail = false;
  List<AssetSavedFilter> items = [];
  final mutations = <String>[];
  @override
  Future<List<AssetSavedFilter>> listSavedFilters() async {
    lists++;
    if (fail) throw StateError('synthetic failure');
    return items;
  }

  @override
  Future<AssetSavedFilter> createSavedFilter(
    String name,
    AssetSavedFilterQuery query,
  ) async {
    mutations.add('create');
    final item = AssetSavedFilter.fromJson({
      'id': '11111111-1111-4111-8111-111111111111',
      'name': name,
      'version': 1,
      'schemaVersion': 1,
      'query': query.values,
    });
    items = [item];
    return item;
  }

  @override
  Future<AssetSavedFilter> updateSavedFilter(
    AssetSavedFilter original,
    String name,
    AssetSavedFilterQuery query,
  ) async {
    mutations.add('update');
    final item = AssetSavedFilter.fromJson({
      'id': original.id,
      'name': name,
      'version': original.version + 1,
      'schemaVersion': 1,
      'query': query.values,
    });
    items = [item];
    return item;
  }

  @override
  Future<void> deleteSavedFilter(AssetSavedFilter original) async {
    mutations.add('delete');
    items = [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AssetSavedFilterQuery sampleQuery() => AssetSavedFilterQuery.fromJson({
  'q': '%_',
  'status': '',
  'category': '',
  'sort': 'updated_desc',
  'locationMode': 'all',
  'location': '',
  'warranty': 'all',
  'asOf': '',
  'checkMode': 'all',
  'checkBefore': '',
  'checkOnOrAfter': '',
});

class InventorySavedStore extends FakeStore implements AssetSavedFilterSource {
  final savedViews = FakeSavedSource();
  @override
  Future<List<AssetSavedFilter>> listSavedFilters() =>
      savedViews.listSavedFilters();
  @override
  Future<AssetSavedFilter> createSavedFilter(
    String name,
    AssetSavedFilterQuery query,
  ) => savedViews.createSavedFilter(name, query);
  @override
  Future<AssetSavedFilter> updateSavedFilter(
    AssetSavedFilter original,
    String name,
    AssetSavedFilterQuery query,
  ) => savedViews.updateSavedFilter(original, name, query);
  @override
  Future<void> deleteSavedFilter(AssetSavedFilter original) =>
      savedViews.deleteSavedFilter(original);
}

class WarrantySavedStore extends InventorySavedStore
    implements AssetWarrantySource {
  final references = <String>[];
  @override
  Future<AssetWarrantyPage> listWarranty({
    String sort = 'updated_desc',
    required String query,
    required String status,
    String category = '',
    required String warranty,
    String asOf = '',
    required int offset,
  }) async {
    references.add(asOf);
    return AssetWarrantyPage.fromJson(
      {
        'items': <Object?>[],
        'nextOffset': null,
        'warranty': warranty,
        'asOf': asOf,
        'through': assetWarrantyThrough(asOf),
      },
      warranty: warranty,
      asOf: asOf,
      offset: offset,
    );
  }
}

void main() {
  testWidgets(
    'saved fixed warranty reference survives Apply Refresh and Back',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = WarrantySavedStore();
      final query = AssetSavedFilterQuery.fromJson({
        ...sampleQuery().values,
        'warranty': 'expired',
        'asOf': '2024-02-29',
      });
      await store.savedViews.createSavedFilter('Fixed leap reference', query);
      await tester.pumpWidget(
        MaterialApp(
          home: AssetsPage(
            store: store,
            enableSavedFilters: true,
            enableAssetDates: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Saved filters'));
      await tester.tap(find.text('Saved filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use as draft'));
      await tester.pumpAndSettle();
      expect(store.references, isEmpty);
      expect(
        find.text('Draft fixed warranty reference: 2024-02-29'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Apply filters'));
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      expect(store.references, ['2024-02-29']);
      await tester.ensureVisible(find.text('Refresh inventory'));
      await tester.tap(find.text('Refresh inventory'));
      await tester.pumpAndSettle();
      expect(store.references, ['2024-02-29', '2024-02-29']);
      await tester.ensureVisible(find.text('Saved filters'));
      await tester.tap(find.text('Saved filters'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(store.references.length, 2);
      expect(store.writes, 0);
    },
  );

  testWidgets(
    'saving uses successful applied query despite draft and later load failure',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = InventorySavedStore();
      await tester.pumpWidget(
        MaterialApp(home: AssetsPage(store: store, enableSavedFilters: true)),
      );
      await tester.pumpAndSettle();
      final search = find.widgetWithText(TextField, 'Search assets');
      await tester.enterText(search, 'Applied search');
      await tester.ensureVisible(find.text('Apply filters'));
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(search);
      await tester.enterText(search, 'Unsent draft');
      store.failure = const AssetFailure('Synthetic failed load');
      await tester.ensureVisible(find.text('Apply filters'));
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Saved filters'));
      await tester.tap(find.text('Saved filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save applied filters'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Last good query');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(store.savedViews.items.single.query.values['q'], 'Applied search');
      expect(store.writes, 0);
    },
  );

  testWidgets(
    'failed reload preserves visible views but blocks writes until successful reload',
    (tester) async {
      final source = FakeSavedSource();
      await source.createSavedFilter('Kept view', sampleQuery());
      await tester.pumpWidget(
        MaterialApp(
          home: SavedFiltersPage(
            source: source,
            applied: sampleQuery(),
            location: false,
            warranty: false,
            check: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      source.fail = true;
      await tester.tap(find.text('Reload saved filters'));
      await tester.pumpAndSettle();
      expect(find.text('Kept view'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save applied filters'),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.textContaining('Reload before another write'),
        findsOneWidget,
      );
      source.fail = false;
      await tester.tap(find.text('Reload saved filters'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save applied filters'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('saved filters render $width at 200%', (tester) async {
      tester.view.physicalSize = Size(width, 1600);
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
      final source = FakeSavedSource();
      await source.createSavedFilter('Stored room %_1', sampleQuery());
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
            child: SavedFiltersPage(
              source: source,
              applied: sampleQuery(),
              location: false,
              warranty: false,
              check: false,
            ),
          ),
        ),
      );
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
            '$directory/saved-filters-${width.toInt()}-200.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
    });
  }

  testWidgets(
    'select fills draft only; explicit Apply and Refresh preserve applied definition',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = InventorySavedStore();
      final query = AssetSavedFilterQuery.fromJson({
        ...sampleQuery().values,
        'q': 'Synthetic',
        'status': 'repair',
        'sort': 'name_asc',
      });
      await store.savedViews.createSavedFilter('Repairs', query);
      await tester.pumpWidget(
        MaterialApp(home: AssetsPage(store: store, enableSavedFilters: true)),
      );
      await tester.pumpAndSettle();
      final baseline = store.calls.length;
      await tester.ensureVisible(find.text('Saved filters'));
      await tester.tap(find.text('Saved filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use as draft'));
      await tester.pumpAndSettle();
      expect(store.calls.length, baseline);
      final search = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Search assets'),
      );
      expect(search.controller!.text, 'Synthetic');
      expect(
        find.byKey(const ValueKey('saved-draft-_status-repair')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Apply filters'));
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      expect(store.calls.last, 'Synthetic|repair|0');
      expect(store.sorts.last, 'name_asc');
      await tester.ensureVisible(find.text('Refresh inventory'));
      await tester.tap(find.text('Refresh inventory'));
      await tester.pumpAndSettle();
      expect(store.calls.last, 'Synthetic|repair|0');
      expect(store.writes, 0);
    },
  );

  testWidgets('explicit save rename delete and Cancel never touch assets', (
    tester,
  ) async {
    final source = FakeSavedSource();
    await tester.pumpWidget(
      MaterialApp(
        home: SavedFiltersPage(
          source: source,
          applied: sampleQuery(),
          location: false,
          warranty: false,
          check: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save applied filters'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'My filters');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(source.mutations, ['create']);
    expect(find.text('My filters'), findsOneWidget);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Renamed');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(source.mutations, ['create', 'update']);
    await tester.tap(find.text('Delete saved filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(source.items.single.name, 'Renamed');
    expect(source.mutations.length, 2);
    await tester.tap(find.text('Delete saved filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete saved filter'));
    await tester.pumpAndSettle();
    expect(source.mutations, ['create', 'update', 'delete']);
    expect(find.text('No saved filters.'), findsOneWidget);
  });

  testWidgets('empty list loads once and cannot save without applied query', (
    tester,
  ) async {
    final source = FakeSavedSource();
    await tester.pumpWidget(
      MaterialApp(
        home: SavedFiltersPage(
          source: source,
          applied: null,
          location: false,
          warranty: false,
          check: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(source.lists, 1);
    expect(find.text('No saved filters.'), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save applied filters'),
    );
    expect(save.onPressed, isNull);
    await tester.tap(find.text('Reload saved filters'));
    await tester.pumpAndSettle();
    expect(source.lists, 2);
  });
}

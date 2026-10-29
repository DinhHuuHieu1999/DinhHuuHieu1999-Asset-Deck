import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:asset_desk/assets_page.dart';
import 'package:asset_desk/api/asset.dart';
import 'package:asset_desk/api/asset_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'asset_location_page_test.dart' show LocationStore;
import 'assets_page_test.dart' show FakeStore, open;
import 'asset_test.dart' show record;
import 'asset_warranty_page_test.dart' show WarrantyStore, openWarranty;

class ResetLocationStore extends LocationStore {
  final sortsSeen = <String>[];
  Completer<AssetLocationPage>? pending;
  @override
  Future<AssetLocationPage> listLocations({
    String sort = 'updated_desc',
    required String query,
    required String status,
    String category = '',
    required int offset,
    String locationMode = 'all',
    String? location,
    String warranty = '',
    String asOf = '',
  }) async {
    sortsSeen.add(sort);
    final result = await super.listLocations(
      sort: sort,
      query: query,
      status: status,
      category: category,
      offset: offset,
      locationMode: locationMode,
      location: location,
      warranty: warranty,
      asOf: asOf,
    );
    return pending == null ? result : await pending!.future;
  }
}

Finder dropdown(String label) => find.byWidgetPredicate(
  (w) =>
      w is DropdownButtonFormField<String> && w.decoration.labelText == label,
);
Finder input(String label) => find.widgetWithText(TextField, label);

Future<void> reveal(WidgetTester tester, Finder target) async {
  final scrollable = find
      .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
      .first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(target, 200, scrollable: scrollable);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> press(WidgetTester tester, String label) async {
  await reveal(tester, find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String field, String value) async {
  await reveal(tester, dropdown(field));
  await tester.tap(dropdown(field));
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String label, String text) async {
  await reveal(tester, input(label));
  await tester.enterText(input(label), text);
  await tester.pump();
}

Future<void> openOptional(WidgetTester tester, ResetLocationStore store) async {
  tester.view.physicalSize = const Size(1100, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: AssetsPage(
        store: store,
        enableAssetDates: true,
        enableAssetLocation: true,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> applyCombined(WidgetTester tester) async {
  await enter(tester, 'Search assets', 'Synthetic');
  await enter(tester, 'Category filter', 'fixture');
  await choose(tester, 'Status filter', 'stored');
  await choose(tester, 'Sort inventory', 'Name A-Z');
  await choose(tester, 'Warranty filter (UTC)', 'Expiring within 30 days');
  await choose(tester, 'Location filter', 'Exact location');
  await enter(tester, 'Exact location', 'Synthetic room %_1');
  await press(tester, 'Apply filters');
}

void main() {
  testWidgets(
    'reset clears all applied filters and drafts, page and warranty reference; keeps applied sort',
    (tester) async {
      final store = ResetLocationStore()..more = true;
      await openOptional(tester, store);
      await applyCombined(tester);
      await press(tester, 'Next page');
      expect(store.locationCalls.last['offset'], 50);
      await choose(tester, 'Sort inventory', 'Updated most recently');
      await enter(tester, 'Search assets', 'Unapplied draft');
      final count = store.locationCalls.length;
      await press(tester, 'Reset filters');
      expect(store.locationCalls.length, count + 1);
      expect(store.locationCalls.last, {
        'q': '',
        'status': '',
        'category': '',
        'offset': 0,
        'mode': 'all',
        'location': null,
        'warranty': '',
        'asOf': '',
      });
      expect(store.sortsSeen.last, 'name_asc');
      await reveal(tester, dropdown('Status filter'));
      expect(
        tester.state<FormFieldState<String>>(dropdown('Status filter')).value,
        '',
      );
      await reveal(tester, dropdown('Warranty filter (UTC)'));
      expect(
        tester
            .state<FormFieldState<String>>(dropdown('Warranty filter (UTC)'))
            .value,
        '',
      );
      await reveal(tester, dropdown('Location filter'));
      expect(
        tester.state<FormFieldState<String>>(dropdown('Location filter')).value,
        'all',
      );
      await reveal(tester, input('Search assets'));
      expect(
        tester.widget<TextField>(input('Search assets')).controller!.text,
        '',
      );
      await reveal(tester, input('Category filter'));
      expect(
        tester.widget<TextField>(input('Category filter')).controller!.text,
        '',
      );
      await press(tester, 'Refresh inventory');
      expect(store.locationCalls.last['offset'], 0);
      expect(store.locationCalls.last['warranty'], '');
      expect(store.sortsSeen.last, 'name_asc');
      expect(store.writes + store.locationWrites, 0);
    },
  );

  testWidgets(
    'failed reset retains applied scope, page and draft controls; refresh uses old scope',
    (tester) async {
      final store = ResetLocationStore()..more = true;
      await openOptional(tester, store);
      await applyCombined(tester);
      await press(tester, 'Next page');
      final before = Map<String, Object?>.of(store.locationCalls.last);
      await enter(tester, 'Search assets', 'Unsaved search');
      store.fail = true;
      await press(tester, 'Reset filters');
      expect(find.textContaining('may be stale'), findsOneWidget);
      expect(find.text('Laptop'), findsOneWidget);
      expect(find.textContaining('Page 2'), findsOneWidget);
      await reveal(tester, input('Search assets'));
      expect(
        tester.widget<TextField>(input('Search assets')).controller!.text,
        'Unsaved search',
      );
      await reveal(tester, dropdown('Status filter'));
      expect(
        tester.state<FormFieldState<String>>(dropdown('Status filter')).value,
        'stored',
      );
      store.fail = false;
      await press(tester, 'Refresh inventory');
      // Refresh intentionally starts page one, but retains the last successful filters.
      expect(store.locationCalls.last, {...before, 'offset': 0, 'asOf': ''});
      expect(store.sortsSeen.last, 'name_asc');
      expect(store.writes + store.locationWrites, 0);
    },
  );

  testWidgets(
    'reset bypasses invalid exact-location draft and clears inline error on success',
    (tester) async {
      final store = ResetLocationStore();
      await openOptional(tester, store);
      await choose(tester, 'Location filter', 'Exact location');
      await press(tester, 'Apply filters');
      expect(store.locationCalls.length, 1);
      expect(find.textContaining('Enter a location'), findsOneWidget);
      await press(tester, 'Reset filters');
      expect(store.locationCalls.length, 2);
      expect(store.locationCalls.last['mode'], 'all');
      expect(find.textContaining('Enter a location'), findsNothing);
      await press(tester, 'Apply filters');
      expect(store.locationCalls.length, 3);
    },
  );

  testWidgets(
    'reset works with optional capabilities disabled and keeps default sort',
    (tester) async {
      final store = FakeStore();
      await open(tester, store);
      await enter(tester, 'Search assets', '%_');
      await press(tester, 'Apply filters');
      await press(tester, 'Reset filters');
      expect(store.calls.last, '||0');
      expect(store.sorts.last, 'updated_desc');
      expect(store.writes, 0);
    },
  );

  testWidgets(
    'pending reset disables repeated resets and Apply; disposal ignores late result',
    (tester) async {
      final store = ResetLocationStore();
      await openOptional(tester, store);
      store.pending = Completer<AssetLocationPage>();
      await reveal(tester, find.text('Reset filters'));
      await tester.tap(find.text('Reset filters'));
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Reset filters'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply filters'),
            )
            .onPressed,
        isNull,
      );
      expect(store.locationCalls.length, 2);
      await tester.pumpWidget(const MaterialApp(home: Text('Signed out')));
      store.pending!.complete(
        AssetLocationPage([
          AssetLocationEntry(AssetRecord.fromJson(record()), null),
        ], null),
      );
      await tester.pumpAndSettle();
      expect(find.text('Signed out'), findsOneWidget);
      expect(find.text('Laptop'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reset leaves warranty-only path and subsequent Apply stays unfiltered',
    (tester) async {
      final store = WarrantyStore();
      await openWarranty(tester, store);
      await choose(tester, 'Warranty filter (UTC)', 'Expired');
      await press(tester, 'Apply filters');
      expect(store.warrantyCalls.last['warranty'], 'expired');
      final calls = store.warrantyCalls.length;
      await press(tester, 'Reset filters');
      expect(store.calls.last, '||0');
      expect(store.warrantyCalls.length, calls);
      await press(tester, 'Apply filters');
      expect(store.calls.last, '||0');
      expect(store.warrantyCalls.length, calls);
      expect(store.writes, 0);
    },
  );

  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('reset controls render $width at 200%', (tester) async {
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
            child: AssetsPage(
              store: LocationStore(),
              enableAssetDates: true,
              enableAssetLocation: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Refresh inventory'));
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
      if (directory != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$directory/filters-${width.toInt()}-200.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}

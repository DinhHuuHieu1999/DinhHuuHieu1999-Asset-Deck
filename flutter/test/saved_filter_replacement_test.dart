import 'package:asset_desk/assets_page.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:flutter/services.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset_saved_filter.dart';
import 'package:asset_desk/saved_filters_page.dart';

import 'saved_filters_page_test.dart'
    show FakeSavedSource, InventorySavedStore, sampleQuery;

class ReplacementSource extends FakeSavedSource {
  bool reject = false;
  int? submittedVersion;
  @override
  Future<AssetSavedFilter> updateSavedFilter(
    AssetSavedFilter original,
    String name,
    AssetSavedFilterQuery query,
  ) async {
    submittedVersion = original.version;
    if (reject) {
      mutations.add('rejected');
      throw StateError('conflict or uncertain acknowledgement');
    }
    return super.updateSavedFilter(original, name, query);
  }
}

void main() {
  late ReplacementSource source;
  late AssetSavedFilterQuery applied;
  setUp(() {
    source = ReplacementSource();
    source.items = [
      AssetSavedFilter.fromJson({
        'id': '11111111-1111-4111-8111-111111111111',
        'name': 'Keep this name',
        'version': 7,
        'schemaVersion': 1,
        'query': sampleQuery().values,
      }),
    ];
    applied = AssetSavedFilterQuery.fromJson({
      ...sampleQuery().values,
      'q': 'Applied only',
      'status': 'repair',
    });
  });
  Future<void> open(
    WidgetTester tester, {
    AssetSavedFilterQuery? query,
    bool location = true,
  }) async {
    tester.view.physicalSize = const Size(1100, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: SavedFiltersPage(
          source: source,
          applied: query ?? applied,
          location: location,
          warranty: true,
          check: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> review(WidgetTester tester) async {
    final button = find.text('Replace with applied filters');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'inventory replacement uses last successful Apply, never failed draft',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = InventorySavedStore();
      await store.savedViews.createSavedFilter('Preserved name', sampleQuery());
      await tester.pumpWidget(
        MaterialApp(home: AssetsPage(store: store, enableSavedFilters: true)),
      );
      await tester.pumpAndSettle();
      final search = find.widgetWithText(TextField, 'Search assets');
      await tester.enterText(search, 'Successfully applied');
      await tester.ensureVisible(find.text('Apply filters'));
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(search);
      await tester.enterText(search, 'Failed unsent definition');
      store.failure = const AssetFailure('Synthetic load failure');
      await tester.ensureVisible(find.text('Apply filters'));
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      final reads = store.calls.length;
      await tester.ensureVisible(find.text('Saved filters'));
      await tester.tap(find.text('Saved filters'));
      await tester.pumpAndSettle();
      await review(tester);
      expect(find.textContaining('Successfully applied'), findsOneWidget);
      expect(find.textContaining('Failed unsent definition'), findsNothing);
      await tester.tap(find.text('Confirm replacement'));
      await tester.pumpAndSettle();
      expect(store.savedViews.items.single.name, 'Preserved name');
      expect(
        store.savedViews.items.single.query.values['q'],
        'Successfully applied',
      );
      expect(store.savedViews.mutations, ['create', 'update']);
      expect(store.writes, 0);
      expect(store.calls.length, reads);
    },
  );
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('replacement dialog render $width at 200%', (tester) async {
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
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            theme: ThemeData(fontFamily: font == null ? null : 'Capture'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: SavedFiltersPage(
              source: source,
              applied: applied,
              location: true,
              warranty: true,
              check: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await review(tester);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Confirm replacement'));
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
      if (directory != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$directory/replacement-${width.toInt()}-200.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(source.mutations, isEmpty);
    });
  }
  testWidgets('preview and Cancel never write or change existing definition', (
    tester,
  ) async {
    await open(tester);
    await review(tester);
    expect(find.text('Currently saved'), findsOneWidget);
    expect(find.text('Applied replacement'), findsOneWidget);
    expect(source.mutations, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(source.items.single.query.values['q'], '%_');
    expect(source.mutations, isEmpty);
  });
  testWidgets(
    'confirm preserves name and sends original version with applied query',
    (tester) async {
      await open(tester);
      await review(tester);
      await tester.tap(find.text('Confirm replacement'));
      await tester.pumpAndSettle();
      expect(source.mutations, ['update']);
      expect(source.submittedVersion, 7);
      expect(source.items.single.name, 'Keep this name');
      expect(source.items.single.version, 8);
      expect(source.items.single.query.values, applied.values);
      expect(source.lists, 2);
    },
  );
  testWidgets(
    'failed write retains old definition and requires Reload without retry',
    (tester) async {
      source.reject = true;
      await open(tester);
      await review(tester);
      await tester.tap(find.text('Confirm replacement'));
      await tester.pumpAndSettle();
      expect(source.mutations, ['rejected']);
      expect(source.items.single.version, 7);
      expect(source.items.single.query.values['q'], '%_');
      expect(
        find.textContaining('Reload before another write'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(
                OutlinedButton,
                'Replace with applied filters',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Reload saved filters'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(
                OutlinedButton,
                'Replace with applied filters',
              ),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'identical and unsupported applied definitions disable replacement',
    (tester) async {
      await open(tester, query: sampleQuery());
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(
                OutlinedButton,
                'Replace with applied filters',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      await open(
        tester,
        query: AssetSavedFilterQuery.fromJson({
          ...applied.values,
          'locationMode': 'exact',
          'location': 'Private room',
        }),
        location: false,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(
                OutlinedButton,
                'Replace with applied filters',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(source.mutations, isEmpty);
    },
  );
}

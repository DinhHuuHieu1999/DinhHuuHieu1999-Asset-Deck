import 'dart:io';
import 'dart:ui' as ui;

import 'package:asset_desk/api/asset.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:asset_desk/assets_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'asset_test.dart' show record;

class FakeStore implements AssetStore {
  final calls = <String>[];
  final categories = <String>[];
  AssetFailure? failure;
  int writes = 0;
  AssetInput? saved;
  Map<int, AssetPage>? pages;
  @override
  Future<AssetPage> list({
    required String query,
    required String status,
    String category = '',
    required int offset,
  }) async {
    calls.add('$query|$status|$offset');
    categories.add(category);
    if (failure != null) throw failure!;
    return pages?[offset] ?? AssetPage([AssetRecord.fromJson(record())], null);
  }

  @override
  Future<AssetRecord> create(AssetInput input) async {
    writes++;
    if (failure != null) throw failure!;
    saved = input;
    return AssetRecord.fromJson(record());
  }

  @override
  Future<AssetRecord> update(AssetRecord original, AssetInput input) =>
      create(input);
}

Future<void> open(WidgetTester tester, FakeStore store) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: AssetsPage(store: store)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'filters only apply explicitly; failure preserves loaded identity and results',
    (tester) async {
      final store = FakeStore();
      await open(tester, store);
      await tester.enterText(find.byType(TextField).first, '%_');
      await tester.enterText(
        find.widgetWithText(TextField, 'Category filter'),
        '  Network%_  ',
      );
      expect(store.calls, ['||0']);
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      expect(store.calls.last, '%_||0');
      expect(store.categories.last, 'Network%_');
      store.failure = const AssetFailure('Unable to load');
      await tester.enterText(find.byType(TextField).first, 'other');
      await tester.enterText(
        find.widgetWithText(TextField, 'Category filter'),
        'Other',
      );
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      expect(find.text('Laptop'), findsOneWidget);
      expect(find.textContaining('may be stale'), findsOneWidget);
      expect(
        find.text('Applied search: %_; status: all; category: Network%_'),
        findsOneWidget,
      );
      await tester.tap(find.text('Refresh inventory'));
      await tester.pumpAndSettle();
      expect(store.calls.last, '%_||0');
      expect(store.categories.last, 'Network%_');
    },
  );
  testWidgets('pagination uses loaded filters and supports back navigation', (
    tester,
  ) async {
    final store = FakeStore()
      ..pages = {
        0: AssetPage(
          List.generate(50, (i) => AssetRecord.fromJson(record(i))),
          50,
        ),
        50: AssetPage([AssetRecord.fromJson(record(50))], null),
      };
    await open(tester, store);
    await tester.enterText(find.byType(TextField).first, 'old filter');
    await tester.enterText(
      find.widgetWithText(TextField, 'Category filter'),
      'network',
    );
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'unapplied draft');
    await tester.enterText(
      find.widgetWithText(TextField, 'Category filter'),
      'unapplied category',
    );
    await tester.scrollUntilVisible(
      find.text('Next page'),
      1000,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 50,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next page'));
    await tester.pumpAndSettle();
    expect(store.calls.last, 'old filter||50');
    expect(store.categories.last, 'network');
    expect(find.text('Next page'), findsNothing);
    await tester.ensureVisible(find.text('Previous page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Previous page'));
    await tester.pumpAndSettle();
    expect(store.calls.last, 'old filter||0');
    expect(store.categories.last, 'network');
  });
  testWidgets(
    'invalid category never sends and refresh retains applied filters',
    (tester) async {
      final store = FakeStore();
      await open(tester, store);
      final category = find.widgetWithText(TextField, 'Category filter');
      await tester.enterText(category, 'network');
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      final count = store.calls.length;
      await tester.enterText(category, 'bad\u0000category');
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      expect(store.calls.length, count);
      expect(find.textContaining('Category must be'), findsOneWidget);
      await tester.tap(find.text('Refresh inventory'));
      await tester.pumpAndSettle();
      expect(store.categories.last, 'network');
      expect(store.writes, 0);
    },
  );
  testWidgets('empty first page and traversal boundary are explicit', (
    tester,
  ) async {
    final store = FakeStore()..pages = {0: AssetPage([], null)};
    await open(tester, store);
    expect(find.text('No matching assets.'), findsOneWidget);
    store.failure = const AssetFailure(
      'Pagination limit reached; the list is incomplete. Narrow your filters.',
      statusCode: 422,
    );
    await tester.tap(find.text('Refresh inventory'));
    await tester.pumpAndSettle();
    expect(find.textContaining('list is incomplete'), findsOneWidget);
    expect(find.textContaining('may be stale'), findsOneWidget);
  });
  testWidgets('create validates, saves once and refreshes', (tester) async {
    final store = FakeStore();
    await open(tester, store);
    await tester.tap(find.text('Add asset'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), ' Router ');
    await tester.enterText(find.byType(TextField).at(1), ' Network ');
    await tester.scrollUntilVisible(
      find.text('Save asset'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save asset'));
    await tester.pumpAndSettle();
    expect(store.writes, 1);
    expect(store.saved!.toJson()['name'], 'Router');
    expect(find.text('Asset Desk'), findsOneWidget);
    expect(store.calls, hasLength(2));
  });
  testWidgets('cancel keeps draft or discards without writing', (tester) async {
    final store = FakeStore();
    await open(tester, store);
    await tester.tap(find.text('Add asset'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Draft');
    await tester.scrollUntilVisible(
      find.text('Cancel'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Draft'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Asset Desk'), findsOneWidget);
    expect(store.writes, 0);
  });
  for (final status in [409, 503]) {
    testWidgets(
      'failure $status preserves draft and blocks blind write retry',
      (tester) async {
        final store = FakeStore();
        await open(tester, store);
        await tester.ensureVisible(find.text('Edit asset'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit asset'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'My draft');
        store.failure = AssetFailure('Failure', statusCode: status);
        await tester.scrollUntilVisible(
          find.text('Save asset'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save asset'));
        await tester.pumpAndSettle();
        expect(store.writes, 1);
        expect(find.text('My draft'), findsOneWidget);
        expect(find.textContaining('Your draft is preserved'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save asset'),
              )
              .onPressed,
          isNull,
        );
      },
    );
  }
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('synthetic inventory at width $width and text 200%', (
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
            child: AssetsPage(store: FakeStore()),
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
          final file = File('$directory/inventory-${width.toInt()}-200.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}

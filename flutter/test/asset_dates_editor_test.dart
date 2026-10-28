import 'dart:async';

import 'package:asset_desk/asset_desk_app.dart';

import 'asset_desk_app_test.dart' show FakeSession, login;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:asset_desk/assets_page.dart';

import 'assets_page_test.dart' show FakeStore;

import 'package:asset_desk/api/asset_dates.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:asset_desk/asset_dates_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class DatesStore implements AssetDatesSource {
  int writes = 0;
  AssetDatesInput? submitted;
  Object? failure;
  final original = const AssetDates(
    id: '11111111-1111-4111-8111-111111111111',
    version: 3,
    input: AssetDatesInput(purchasedOn: '2026-01-01', warrantyExpiresOn: null),
  );
  @override
  Future<AssetDates> readDates(String id) async => original;
  @override
  Future<AssetDates> updateDates(
    AssetDates value,
    AssetDatesInput input,
  ) async {
    writes++;
    expect(value.version, 3);
    submitted = input;
    if (failure != null) throw failure!;
    return AssetDates(id: value.id, version: 4, input: input);
  }
}

class DatesInventory extends FakeStore implements AssetDatesSource {
  final dates = DatesStore();
  int reads = 0;
  AssetFailure? readFailure;
  @override
  Future<AssetDates> readDates(String id) async {
    reads++;
    if (readFailure != null) throw readFailure!;
    return AssetDates(id: id, version: 3, input: dates.original.input);
  }

  @override
  Future<AssetDates> updateDates(AssetDates original, AssetDatesInput input) =>
      dates.updateDates(original, input);
}

class DatesSession extends FakeSession implements AssetDatesSource {
  Completer<AssetDates>? delayedDates;
  int dateWrites = 0;
  @override
  Future<AssetDates> readDates(String id) async =>
      delayedDates?.future ??
      Future.value(
        AssetDates(
          id: id,
          version: 3,
          input: const AssetDatesInput(
            purchasedOn: '2026-01-01',
            warrantyExpiresOn: null,
          ),
        ),
      );
  @override
  Future<AssetDates> updateDates(
    AssetDates original,
    AssetDatesInput input,
  ) async {
    dateWrites++;
    return AssetDates(id: original.id, version: 4, input: input);
  }
}

void main() {
  for (final delayed in [false, true]) {
    testWidgets(
      'sign out clears dates ${delayed ? 'pending read' : 'dirty editor'}',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final session = DatesSession();
        await tester.pumpWidget(
          AssetDeskApp(session: session, enableAssetDates: true),
        );
        await tester.pumpAndSettle();
        await login(tester);
        if (delayed) session.delayedDates = Completer<AssetDates>();
        await tester.scrollUntilVisible(
          find.text('Purchase / warranty dates'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Purchase / warranty dates'));
        if (delayed) {
          await tester.pump();
        } else {
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField).first, '2026-03-01');
        }
        await tester.tap(find.text('Sign out'));
        await tester.pumpAndSettle();
        if (delayed) {
          session.delayedDates!.complete(
            const AssetDates(
              id: '11111111-1111-4111-8111-111111111111',
              version: 3,
              input: AssetDatesInput(
                purchasedOn: null,
                warrantyExpiresOn: null,
              ),
            ),
          );
          await tester.pumpAndSettle();
        }
        expect(find.text('Asset dates'), findsNothing);
        expect(find.text('2026-03-01'), findsNothing);
        expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
        expect(session.dateWrites, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'date read failure retains loaded inventory without opening editor',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = DatesInventory()
        ..readFailure = const AssetFailure('Dates unavailable');
      await tester.pumpWidget(
        MaterialApp(home: AssetsPage(store: store, enableAssetDates: true)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Purchase / warranty dates'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Purchase / warranty dates'));
      await tester.pumpAndSettle();
      expect(find.text('Asset dates'), findsNothing);
      expect(find.text('Laptop'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Dates unavailable'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Dates unavailable'), findsOneWidget);
      expect(store.writes, 0);
    },
  );

  testWidgets(
    'inventory dates are opt-in and fetch fresh version before editing',
    (tester) async {
      final store = DatesInventory();
      await tester.pumpWidget(MaterialApp(home: AssetsPage(store: store)));
      await tester.pumpAndSettle();
      expect(find.text('Purchase / warranty dates'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(home: AssetsPage(store: store, enableAssetDates: true)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Purchase / warranty dates').hitTestable(),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Purchase / warranty dates'));
      await tester.pumpAndSettle();
      expect(store.reads, 1);
      expect(find.text('Asset dates'), findsOneWidget);
      expect(find.textContaining('not a warranty backup'), findsOneWidget);
    },
  );

  Future<void> open(WidgetTester tester, DatesStore store) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      AssetDatesEditor(store: store, original: store.original),
                ),
              ),
              child: const Text('Open dates'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open dates'));
    await tester.pumpAndSettle();
  }

  testWidgets('Keep retains draft and Discard leaves without writing', (
    tester,
  ) async {
    final store = DatesStore();
    await open(tester, store);
    await tester.enterText(find.byType(TextField).first, '2026-03-01');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '2026-03-01',
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Open dates'), findsOneWidget);
    expect(store.writes, 0);
  });
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('dates form width $width at text 200%', (tester) async {
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
      final store = DatesStore();
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
            child: AssetDatesEditor(store: store, original: store.original),
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
          final file = File('$directory/dates-${width.toInt()}-200.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.scrollUntilVisible(
        find.text('Save dates'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(store.writes, 0);
    });
  }

  testWidgets('clear purchase explicitly and save once', (tester) async {
    final store = DatesStore();
    await open(tester, store);
    await tester.enterText(find.byType(TextField).first, '');
    await tester.ensureVisible(find.text('Save dates'));
    await tester.tap(find.text('Save dates'));
    await tester.pumpAndSettle();
    expect(store.writes, 1);
    expect(store.submitted!.purchasedOn, isNull);
    expect(find.text('Open dates'), findsOneWidget);
  });
  testWidgets('invalid date stays in draft without request', (tester) async {
    final store = DatesStore();
    await open(tester, store);
    await tester.enterText(find.byType(TextField).first, '1900-02-29');
    await tester.ensureVisible(find.text('Save dates'));
    await tester.tap(find.text('Save dates'));
    await tester.pumpAndSettle();
    expect(store.writes, 0);
    expect(find.textContaining('Use real YYYY-MM-DD'), findsOneWidget);
  });
  testWidgets('conflict retains draft and blocks blind retry', (tester) async {
    final store = DatesStore()
      ..failure = const AssetFailure('Conflict', statusCode: 409);
    await open(tester, store);
    await tester.enterText(find.byType(TextField).first, '2026-02-01');
    await tester.ensureVisible(find.text('Save dates'));
    await tester.tap(find.text('Save dates'));
    await tester.pumpAndSettle();
    expect(store.writes, 1);
    expect(find.textContaining('Your draft is preserved'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save dates'))
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '2026-02-01',
    );
  });
}

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset.dart';
import 'package:asset_desk/api/asset_dates.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:asset_desk/asset_details_page.dart';
import 'package:asset_desk/asset_desk_app.dart';

import 'asset_desk_app_test.dart' show FakeSession;
import 'assets_page_test.dart' show FakeStore, open;
import 'asset_details_test.dart' show Dates;
import 'asset_test.dart' show record;

class EditingStore extends FakeStore {
  AssetRecord? original;
  @override
  Future<AssetRecord> update(AssetRecord original, AssetInput input) {
    this.original = original;
    return super.update(original, input);
  }
}

class PendingEditingSession extends FakeSession {
  final pendingUpdate = Completer<AssetRecord>();
  @override
  Future<AssetRecord> update(AssetRecord original, AssetInput input) {
    writes.add(input);
    return pendingUpdate.future;
  }
}

Future<void> details(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('View details'),
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('View details'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edit asset'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Save edits selected version and reloads applied, not draft query',
    (tester) async {
      final store = EditingStore();
      await open(tester, store);
      await tester.enterText(find.byType(TextField).first, 'applied');
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'unsent');
      await details(tester);
      await tester.enterText(
        find.byType(TextField).first,
        'Edited from details',
      );
      await tester.ensureVisible(find.text('Save asset'));
      await tester.tap(find.text('Save asset'));
      await tester.pumpAndSettle();
      expect(store.original!.id, AssetRecord.fromJson(record()).id);
      expect(store.original!.version, AssetRecord.fromJson(record()).version);
      expect(store.saved!.name, 'Edited from details');
      expect(store.calls.last, 'applied||0');
      expect(store.calls.length, 3);
      expect(find.text('Asset details'), findsNothing);
      expect(find.text('unsent'), findsOneWidget);
    },
  );

  testWidgets('Cancel returns to details without write or reload', (
    tester,
  ) async {
    final store = EditingStore();
    await open(tester, store);
    await details(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Asset details'), findsOneWidget);
    expect(store.calls.length, 1);
    expect(store.writes, 0);
  });

  testWidgets('Unverified optional information never enables editing', (
    tester,
  ) async {
    final pending = Completer<AssetDates>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AssetDetailsPage(
          record: AssetRecord.fromJson(record()),
          datesSource: Dates()..pending = pending.future,
          onEdit: (_) async {
            calls++;
            return false;
          },
        ),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Edit asset'),
          )
          .onPressed,
      isNull,
    );
    pending.completeError(StateError('Synthetic read failure'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Edit asset'),
          )
          .onPressed,
      isNull,
    );
    expect(calls, 0);
  });

  testWidgets('Save on page two preserves page and applied sort', (
    tester,
  ) async {
    final selected = AssetRecord.fromJson({...record(7), 'version': 9});
    final store = EditingStore()
      ..pages = {
        0: AssetPage([AssetRecord.fromJson(record())], 50),
        50: AssetPage([selected], null),
      };
    await open(tester, store);
    await tester.ensureVisible(
      find.byKey(const ValueKey('inventory-sort-updated_desc')),
    );
    await tester.tap(find.byKey(const ValueKey('inventory-sort-updated_desc')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name A-Z').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Apply filters'));
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Next page'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Next page'));
    await tester.pumpAndSettle();
    await details(tester);
    await tester.enterText(find.byType(TextField).first, 'Second page edit');
    await tester.ensureVisible(find.text('Save asset'));
    await tester.tap(find.text('Save asset'));
    await tester.pumpAndSettle();
    expect(identical(store.original, selected), isTrue);
    expect(store.original!.version, 9);
    expect(store.calls.last, '||50');
    expect(store.sorts.last, 'name_asc');
    expect(find.text('Asset details'), findsNothing);
  });

  for (final status in [409, 503]) {
    testWidgets('Details edit $status retains draft and blocks blind retry', (
      tester,
    ) async {
      final store = EditingStore();
      await open(tester, store);
      await details(tester);
      await tester.enterText(
        find.byType(TextField).first,
        'Private edit draft',
      );
      store.failure = AssetFailure('Synthetic rejection', statusCode: status);
      await tester.ensureVisible(find.text('Save asset'));
      await tester.tap(find.text('Save asset'));
      await tester.pumpAndSettle();
      expect(find.text('Private edit draft'), findsOneWidget);
      expect(store.writes, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save asset'),
            )
            .onPressed,
        isNull,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Private edit draft'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Asset details'), findsOneWidget);
      expect(store.calls.length, 1);
      expect(store.writes, 1);
    });
  }

  testWidgets('Session change rejects late successful edit result', (
    tester,
  ) async {
    final session = FakeSession();
    addTearDown(session.close);
    final pending = Completer<bool>();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => AssetDetailsPage(
                    record: AssetRecord.fromJson(record()),
                    session: session,
                    onEdit: (_) => pending.future,
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit asset'));
    await tester.pump();
    session.signOut();
    await tester.pump();
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(find.textContaining('Session changed'), findsOneWidget);
    expect(find.text('Laptop'), findsNothing);
    expect(find.text('Edit asset'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Root sign-out removes details editor and ignores late write result',
    (tester) async {
      final session = PendingEditingSession();
      await session.login('synthetic', 'not-a-real-credential');
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(AssetDeskApp(session: session));
      await tester.pumpAndSettle();
      await details(tester);
      await tester.enterText(
        find.byType(TextField).first,
        'Private pending edit',
      );
      await tester.ensureVisible(find.text('Save asset'));
      await tester.tap(find.text('Save asset'));
      await tester.pump();
      expect(session.writes.length, 1);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      session.pendingUpdate.complete(AssetRecord.fromJson(record()));
      await tester.pumpAndSettle();
      expect(find.text('Private pending edit'), findsNothing);
      expect(find.text('Asset details'), findsNothing);
      expect(find.text('Laptop'), findsNothing);
      expect(session.writes.length, 1);
      expect(find.text('Sign in'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('Editable details render at $width and text 200%', (
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
            child: AssetDetailsPage(
              record: AssetRecord.fromJson(record()),
              datesSource: Dates(),
              onEdit: (_) async => false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Edit asset'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
      if (directory != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '$directory/editable-details-${width.toInt()}-200.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.scrollUntilVisible(
        find.text('Updated (UTC)'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

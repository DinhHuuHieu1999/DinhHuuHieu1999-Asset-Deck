import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:asset_desk/asset_editor.dart';
import 'package:asset_desk/api/asset.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'assets_page_test.dart' show FakeStore, open;
import 'asset_test.dart' show record;

class DuplicateStore extends FakeStore {
  int creates = 0, updates = 0;
  DuplicateStore() {
    pages = {
      0: AssetPage([
        AssetRecord.fromJson({
          ...record(),
          'name': 'Synthetic source',
          'serial': 'PRIVATE-SERIAL',
          'status': 'stored',
          'notes': 'Source notes',
        }),
      ], null),
    };
  }
  @override
  Future<AssetRecord> create(AssetInput input) {
    creates++;
    return super.create(input);
  }

  @override
  Future<AssetRecord> update(AssetRecord original, AssetInput input) {
    updates++;
    return super.update(original, input);
  }
}

Future<void> duplicate(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('View details'),
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('View details'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Duplicate as draft'));
  await tester.pumpAndSettle();
}

String field(WidgetTester tester, int index) =>
    tester.widget<TextField>(find.byType(TextField).at(index)).controller!.text;

void main() {
  testWidgets(
    'duplicate is create-only, blank serial, explicit save and applied reload',
    (tester) async {
      final store = DuplicateStore();
      await open(tester, store);
      await tester.enterText(find.byType(TextField).first, 'Synthetic');
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'unsent');
      await duplicate(tester);
      expect(find.text('Duplicate asset draft'), findsOneWidget);
      expect(field(tester, 0), 'Synthetic source');
      expect(field(tester, 1), 'Computers');
      expect(field(tester, 2), '');
      expect(field(tester, 3), 'Source notes');
      expect(store.writes, 0);
      await tester.ensureVisible(find.text('Save asset'));
      await tester.tap(find.text('Save asset'));
      await tester.pumpAndSettle();
      expect(store.creates, 1);
      expect(store.updates, 0);
      expect(store.saved!.serial, '');
      expect(store.saved!.status, 'stored');
      expect(store.saved!.toJson().keys.toSet(), {
        'name',
        'category',
        'serial',
        'status',
        'notes',
      });
      expect(store.pages![0]!.items.single.input.serial, 'PRIVATE-SERIAL');
      expect(store.calls.last, 'Synthetic||0');
      expect(find.text('unsent'), findsOneWidget);
    },
  );

  testWidgets(
    'unchanged copied draft requires discard; Keep preserves fields',
    (tester) async {
      final store = DuplicateStore();
      await open(tester, store);
      await duplicate(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(field(tester, 0), 'Synthetic source');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Asset details'), findsOneWidget);
      expect(store.writes, 0);
      expect(store.calls.length, 1);
    },
  );

  testWidgets(
    'failure retains draft and does not automatically retry or update source',
    (tester) async {
      final store = DuplicateStore();
      await open(tester, store);
      await duplicate(tester);
      await tester.enterText(find.byType(TextField).at(2), 'NEW-SERIAL');
      store.failure = const AssetFailure('Synthetic create failed');
      await tester.ensureVisible(find.text('Save asset'));
      await tester.tap(find.text('Save asset'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Save outcome is unknown.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save asset'),
            )
            .onPressed,
        isNull,
      );
      expect(field(tester, 2), 'NEW-SERIAL');
      await tester.pump(const Duration(seconds: 3));
      expect(store.creates, 1);
      expect(store.updates, 0);
      expect(store.pages![0]!.items.single.input.serial, 'PRIVATE-SERIAL');
    },
  );
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('duplicate draft render $width at text 200%', (tester) async {
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
      final store = DuplicateStore();
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
            child: AssetEditor.duplicate(
              store: store,
              source: store.pages![0]!.items.single,
            ),
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
          final file = File(
            '$directory/duplicate-draft-${width.toInt()}-200.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.scrollUntilVisible(
        find.text('Save asset'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(store.writes, 0);
    });
  }
}

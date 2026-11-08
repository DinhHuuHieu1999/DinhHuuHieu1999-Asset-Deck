import 'dart:io';
import 'dart:ui' as ui;

import 'package:asset_desk/api/asset.dart';
import 'package:asset_desk/api/asset_check.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:asset_desk/asset_check_editor.dart';
import 'package:asset_desk/asset_details_page.dart';
import 'package:asset_desk/assets_page.dart';

import 'assets_page_test.dart' show FakeStore;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'asset_check_editor_test.dart' show CheckFake, original;
import 'asset_test.dart' show record;

DateTime now() => DateTime.parse('2026-11-07T00:30:00+07:00');

Future<void> openToday(WidgetTester tester, CheckFake source) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<bool>(
                builder: (_) => AssetCheckEditor(
                  source: source,
                  original: original,
                  useToday: true,
                  clock: now,
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
}

class MatchingCheck extends CheckFake {
  bool mismatch = false;
  @override
  Future<AssetCheck> readCheckDate(String id) async =>
      AssetCheck(id: id, version: mismatch ? 2 : 1, lastCheckedOn: null);
}

class TodayStore extends FakeStore implements AssetCheckSource {
  AssetCheck? submitted;
  String? savedDate;
  @override
  Future<AssetCheck> readCheckDate(String id) async =>
      AssetCheck(id: id, version: 1, lastCheckedOn: null);
  @override
  Future<AssetCheck> updateCheckDate(AssetCheck original, String? date) async {
    submitted = original;
    savedDate = date;
    return AssetCheck(id: original.id, version: 2, lastCheckedOn: date);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected operation');
}

void main() {
  testWidgets(
    'inventory today action saves verified version and reloads applied query',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = TodayStore();
      await tester.pumpWidget(
        MaterialApp(home: AssetsPage(store: store, enableAssetCheck: true)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'applied');
      await tester.ensureVisible(find.text('Apply filters'));
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'unsent');
      await tester.scrollUntilVisible(
        find.text('View details'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('View details'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Mark checked today (UTC)'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Mark checked today (UTC)'));
      await tester.pumpAndSettle();
      expect(store.submitted, isNull);
      final expected = DateTime.now().toUtc().toIso8601String().substring(
        0,
        10,
      );
      expect(find.text(expected), findsOneWidget);
      await tester.ensureVisible(find.text('Save check date'));
      await tester.tap(find.text('Save check date'));
      await tester.pumpAndSettle();
      expect(store.savedDate, expected);
      expect(store.submitted!.id, record()['id']);
      expect(store.submitted!.version, 1);
      expect(store.calls.last, 'applied||0');
      expect(store.writes, 0);
      expect(find.text('unsent'), findsOneWidget);
    },
  );

  testWidgets('UTC review prefill never writes until explicit Save', (
    tester,
  ) async {
    final source = CheckFake();
    await openToday(tester, source);
    expect(find.text('2026-11-06'), findsOneWidget);
    expect(find.textContaining('Nothing is saved yet'), findsOneWidget);
    expect(source.writes, 0);
    await tester.tap(find.text('Save check date'));
    await tester.pumpAndSettle();
    expect(source.writes, 1);
    expect(source.saved, '2026-11-06');
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('Cancel keeps or discards today draft without writing', (
    tester,
  ) async {
    final source = CheckFake();
    await openToday(tester, source);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('2026-11-06'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(source.writes, 0);
  });

  testWidgets('review allows manual correction before saving', (tester) async {
    final source = CheckFake();
    await openToday(tester, source);
    await tester.enterText(find.byType(TextField), '2024-02-29');
    await tester.tap(find.text('Save check date'));
    await tester.pumpAndSettle();
    expect(source.saved, '2024-02-29');
    expect(source.writes, 1);
  });

  for (final status in [409, 0]) {
    testWidgets('failure $status preserves today draft without retry', (
      tester,
    ) async {
      final source = CheckFake()
        ..failure = AssetFailure(
          'Synthetic failure',
          statusCode: status == 0 ? null : status,
        );
      await openToday(tester, source);
      await tester.tap(find.text('Save check date'));
      await tester.pumpAndSettle();
      expect(find.text('2026-11-06'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save check date'),
            )
            .onPressed,
        isNull,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(source.writes, 1);
    });
  }

  for (final mismatch in [false, true]) {
    testWidgets('details action uses verified check snapshot: $mismatch', (
      tester,
    ) async {
      final source = MatchingCheck()..mismatch = mismatch;
      AssetCheck? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: AssetDetailsPage(
            record: AssetRecord.fromJson(record()),
            checkSource: source,
            onCheckToday: (check) async {
              selected = check;
              return false;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.widgetWithText(
        OutlinedButton,
        'Mark checked today (UTC)',
      );
      await tester.scrollUntilVisible(
        button,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      if (mismatch) {
        expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      } else {
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(selected!.id, record()['id']);
        expect(selected!.version, 1);
      }
      expect(source.writes, 0);
    });
  }

  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('today details action render $width at text 200%', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      final font = Platform.environment['ASSET_DESK_UI_CAPTURE_FONT'];
      if (font != null) {
        await (FontLoader('Capture')..addFont(
              Future.value(ByteData.sublistView(File(font).readAsBytesSync())),
            ))
            .load();
      }
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
              checkSource: MatchingCheck(),
              onCheckToday: (_) async => false,
              onEditCheck: (_) async => false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Mark checked today (UTC)'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
      if (directory != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '$directory/check-today-details-${width.toInt()}-200.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });

    testWidgets('today review render $width at text 200%', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final font = Platform.environment['ASSET_DESK_UI_CAPTURE_FONT'];
      if (font != null) {
        await (FontLoader('Capture')..addFont(
              Future.value(ByteData.sublistView(File(font).readAsBytesSync())),
            ))
            .load();
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
            child: AssetCheckEditor(
              source: CheckFake(),
              original: original,
              useToday: true,
              clock: now,
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
          final file = File('$directory/check-today-${width.toInt()}-200.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.scrollUntilVisible(
        find.text('Save check date'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

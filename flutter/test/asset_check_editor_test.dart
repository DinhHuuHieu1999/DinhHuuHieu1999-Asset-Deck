import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:asset_desk/api/asset_check.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:asset_desk/asset_check_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class CheckFake implements AssetCheckSource {
  int writes = 0;
  String? saved;
  AssetFailure? failure;
  Completer<AssetCheck>? pending;
  @override
  Future<AssetCheck> readCheckDate(String id) async => original;
  @override
  Future<AssetCheck> updateCheckDate(
    AssetCheck original,
    String? location,
  ) async {
    writes++;
    if (failure != null) throw failure!;
    if (pending != null) return pending!.future;
    saved = location;
    return AssetCheck(
      id: original.id,
      version: original.version + 1,
      lastCheckedOn: location,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected operation');
}

const original = AssetCheck(
  id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  version: 1,
  lastCheckedOn: '2024-01-01',
);
Future<void> open(WidgetTester tester, CheckFake source) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<bool>(
                builder: (_) =>
                    AssetCheckEditor(source: source, original: original),
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

void main() {
  testWidgets('pending save blocks repeated submission and leaving', (
    tester,
  ) async {
    final source = CheckFake()..pending = Completer<AssetCheck>();
    await open(tester, source);
    await tester.enterText(find.byType(TextField), '2024-02-29');
    await tester.tap(find.text('Save check date'));
    await tester.pump();
    expect(source.writes, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save check date'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Cancel'))
          .onPressed,
      isNull,
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
    source.pending!.complete(
      const AssetCheck(
        id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        version: 2,
        lastCheckedOn: '2024-02-29',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(source.writes, 1);
  });
  testWidgets(
    'definitely unsent rejection preserves draft and allows explicit correction',
    (tester) async {
      final source = CheckFake()
        ..failure = const AssetFailure(
          'Synthetic validation failure',
          statusCode: 400,
        );
      await open(tester, source);
      await tester.enterText(find.byType(TextField), '2024-02-29');
      await tester.tap(find.text('Save check date'));
      await tester.pumpAndSettle();
      expect(find.text('2024-02-29'), findsOneWidget);
      expect(
        find.textContaining('Synthetic validation failure'),
        findsOneWidget,
      );
      expect(source.writes, 1);
      source.failure = null;
      await tester.enterText(find.byType(TextField), '2024-02-28');
      await tester.tap(find.text('Save check date'));
      await tester.pumpAndSettle();
      expect(source.writes, 2);
      expect(source.saved, '2024-02-28');
    },
  );
  testWidgets('save preserves exact date and blank explicitly clears', (
    tester,
  ) async {
    final source = CheckFake();
    await open(tester, source);
    await tester.enterText(find.byType(TextField), '2024-02-29');
    await tester.tap(find.text('Save check date'));
    await tester.pumpAndSettle();
    expect(source.saved, '2024-02-29');
    expect(source.writes, 1);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Save check date'));
    await tester.pumpAndSettle();
    expect(source.saved, isNull);
    expect(source.writes, 2);
  });
  testWidgets('keep draft then discard leaves stored data unchanged', (
    tester,
  ) async {
    final source = CheckFake();
    await open(tester, source);
    await tester.enterText(find.byType(TextField), '2023-01-01');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('2023-01-01'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(source.writes, 0);
    expect(find.text('Open'), findsOneWidget);
  });
  testWidgets('invalid and future dates never send a write', (tester) async {
    final source = CheckFake();
    await open(tester, source);
    for (final value in ['2025-02-29', '9999-12-31', '2024-2-29']) {
      await tester.enterText(find.byType(TextField), value);
      await tester.tap(find.text('Save check date'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter a real date'), findsOneWidget);
      expect(source.writes, 0);
    }
  });
  for (final failure in [
    const AssetFailure('Conflict', statusCode: 409),
    const AssetFailure('Disconnected'),
  ]) {
    testWidgets(
      'failure preserves draft and disables blind resubmission: $failure',
      (tester) async {
        final source = CheckFake()..failure = failure;
        await open(tester, source);
        await tester.enterText(find.byType(TextField), '2023-01-01');
        await tester.tap(find.text('Save check date'));
        await tester.pumpAndSettle();
        expect(find.text('2023-01-01'), findsOneWidget);
        expect(source.writes, 1);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save check date'),
              )
              .onPressed,
          isNull,
        );
      },
    );
  }
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('check date editor reflows at $width and 200 percent', (
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
            child: AssetCheckEditor(source: CheckFake(), original: original),
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
            '$directory/check-date-editor-${width.toInt()}-200.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
    });
  }
}

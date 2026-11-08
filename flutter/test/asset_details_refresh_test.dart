import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'asset_details_test.dart' show Dates, Location;
import 'asset_desk_app_test.dart' show FakeSession;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset.dart';
import 'package:asset_desk/api/asset_read.dart';
import 'package:asset_desk/asset_details_page.dart';

import 'asset_test.dart' show record;

class Reader implements AssetReadSource {
  Future<AssetRecord> Function()? next;
  int calls = 0;
  @override
  Future<AssetRecord> readAsset(String id) {
    calls++;
    return next!();
  }
}

void main() {
  testWidgets('version mismatch retains complete previous snapshot', (
    tester,
  ) async {
    final reader = Reader()
      ..next = () async => AssetRecord.fromJson({
        ...record(),
        'name': 'Unverified new name',
        'version': 2,
      });
    await tester.pumpWidget(
      MaterialApp(
        home: AssetDetailsPage(
          record: AssetRecord.fromJson(record()),
          readSource: reader,
          datesSource: Dates(),
          locationSource: Location(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh details'));
    await tester.pumpAndSettle();
    expect(find.text('Unverified new name'), findsNothing);
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('2024-02-29'), findsOneWidget);
    expect(find.textContaining('Previous snapshot retained'), findsOneWidget);
  });
  testWidgets(
    'session invalidation clears private fields and ignores late refresh',
    (tester) async {
      final pending = Completer<AssetRecord>();
      final reader = Reader()..next = () => pending.future;
      final session = FakeSession();
      addTearDown(session.events.close);
      await tester.pumpWidget(
        MaterialApp(
          home: AssetDetailsPage(
            record: AssetRecord.fromJson(record()),
            readSource: reader,
            session: session,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh details'));
      await tester.pump();
      session.signOut();
      await tester.pump();
      pending.complete(
        AssetRecord.fromJson({...record(), 'name': 'Late private asset'}),
      );
      await tester.pumpAndSettle();
      expect(find.text('Laptop'), findsNothing);
      expect(find.text('Late private asset'), findsNothing);
      expect(find.textContaining('Session changed'), findsOneWidget);
    },
  );
  testWidgets('source replacement discards an older in-flight refresh', (
    tester,
  ) async {
    final pending = Completer<AssetRecord>();
    final old = Reader()..next = () => pending.future;
    final replacement = Reader();
    final original = AssetRecord.fromJson(record());
    Widget page(Reader reader) => MaterialApp(
      home: AssetDetailsPage(record: original, readSource: reader),
    );
    await tester.pumpWidget(page(old));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh details'));
    await tester.pump();
    await tester.pumpWidget(page(replacement));
    await tester.pumpAndSettle();
    pending.complete(
      AssetRecord.fromJson({...record(), 'name': 'Discarded response'}),
    );
    await tester.pumpAndSettle();
    expect(find.text('Discarded response'), findsNothing);
    expect(find.text('Laptop'), findsOneWidget);
  });

  testWidgets(
    'refresh commits verified snapshot and failed refresh retains it',
    (tester) async {
      final reader = Reader();
      final original = AssetRecord.fromJson(record());
      final updated = AssetRecord.fromJson({
        ...record(),
        'name': 'Refreshed asset',
        'version': 2,
      });
      reader.next = () async => updated;
      await tester.pumpWidget(
        MaterialApp(
          home: AssetDetailsPage(
            record: original,
            readSource: reader,
            onEdit: (_) async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(reader.calls, 0);
      await tester.tap(find.text('Refresh details'));
      await tester.pumpAndSettle();
      expect(find.text('Refreshed asset'), findsOneWidget);
      reader.next = () async => throw StateError('offline');
      await tester.tap(find.text('Refresh details'));
      await tester.pumpAndSettle();
      expect(find.text('Refreshed asset'), findsOneWidget);
      expect(find.textContaining('Previous snapshot retained'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Edit asset'),
            )
            .onPressed,
        isNull,
      );
      reader.next = () async => updated;
      await tester.tap(find.text('Refresh details'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Previous snapshot retained'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Edit asset'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets('wrong identity never replaces previous snapshot', (
    tester,
  ) async {
    final reader = Reader()
      ..next = () async =>
          AssetRecord.fromJson({...record(1), 'name': 'Wrong asset'});
    await tester.pumpWidget(
      MaterialApp(
        home: AssetDetailsPage(
          record: AssetRecord.fromJson(record()),
          readSource: reader,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh details'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong asset'), findsNothing);
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.textContaining('Previous snapshot retained'), findsOneWidget);
  });
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('refresh details render at $width and text 200%', (
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
              readSource: Reader(),
              datesSource: Dates(),
              locationSource: Location(),
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
          final file = File('$directory/details-${width.toInt()}-200.png');
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

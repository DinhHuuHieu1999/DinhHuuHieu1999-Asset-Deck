import 'dart:io';
import 'dart:ui' as ui;

import 'package:asset_desk/api/asset_location.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:asset_desk/asset_location_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class LocationFake implements AssetLocationSource {
  int writes = 0;
  String? saved;
  AssetFailure? failure;
  @override
  Future<AssetLocation> readLocation(String id) async => original;
  @override
  Future<AssetLocation> updateLocation(
    AssetLocation original,
    String? location,
  ) async {
    writes++;
    if (failure != null) throw failure!;
    saved = location;
    return AssetLocation(
      id: original.id,
      version: original.version + 1,
      location: location,
    );
  }

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
  }) async => AssetLocationPage([], null);
}

const original = AssetLocation(
  id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  version: 1,
  location: 'Office',
);
Future<void> open(WidgetTester tester, LocationFake source) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<bool>(
                builder: (_) =>
                    AssetLocationEditor(source: source, original: original),
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
  testWidgets('save normalizes label and blank explicitly clears', (
    tester,
  ) async {
    final source = LocationFake();
    await open(tester, source);
    await tester.enterText(find.byType(TextField), ' Room A ');
    await tester.tap(find.text('Save location'));
    await tester.pumpAndSettle();
    expect(source.saved, 'Room A');
    expect(source.writes, 1);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Save location'));
    await tester.pumpAndSettle();
    expect(source.saved, isNull);
    expect(source.writes, 2);
  });
  testWidgets('keep draft then discard leaves stored data unchanged', (
    tester,
  ) async {
    final source = LocationFake();
    await open(tester, source);
    await tester.enterText(find.byType(TextField), 'Draft');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Draft'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(source.writes, 0);
    expect(find.text('Open'), findsOneWidget);
  });
  for (final failure in [
    const AssetFailure('Conflict', statusCode: 409),
    const AssetFailure('Disconnected'),
  ]) {
    testWidgets(
      'failure preserves draft and disables blind resubmission: $failure',
      (tester) async {
        final source = LocationFake()..failure = failure;
        await open(tester, source);
        await tester.enterText(find.byType(TextField), 'Draft');
        await tester.tap(find.text('Save location'));
        await tester.pumpAndSettle();
        expect(find.text('Draft'), findsOneWidget);
        expect(source.writes, 1);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save location'),
              )
              .onPressed,
          isNull,
        );
      },
    );
  }
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('location editor reflows at $width and 200 percent', (
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
            child: AssetLocationEditor(
              source: LocationFake(),
              original: original,
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
            '$directory/location-editor-${width.toInt()}-200.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
    });
  }
}

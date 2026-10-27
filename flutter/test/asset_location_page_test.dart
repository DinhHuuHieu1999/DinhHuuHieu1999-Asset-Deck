import 'dart:io';
import 'dart:ui' as ui;

import 'package:asset_desk/api/asset.dart';
import 'package:asset_desk/api/asset_location.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:asset_desk/api/asset_warranty.dart';
import 'package:asset_desk/assets_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'assets_page_test.dart' show FakeStore;
import 'asset_test.dart' show record;
import 'asset_warranty_test.dart' show warrantyFixture;

class LocationStore extends FakeStore
    implements AssetLocationSource, AssetWarrantySource {
  final locationCalls = <Map<String, Object?>>[];
  int reads = 0, locationWrites = 0;
  String? label = 'Office';
  bool fail = false, more = false;
  @override
  Future<AssetLocationPage> listLocations({
    required String query,
    required String status,
    String category = '',
    required int offset,
    String locationMode = 'all',
    String? location,
    String warranty = '',
    String asOf = '',
  }) async {
    locationCalls.add({
      'q': query,
      'status': status,
      'category': category,
      'offset': offset,
      'mode': locationMode,
      'location': location,
      'warranty': warranty,
      'asOf': asOf,
    });
    if (fail) throw const AssetFailure('Synthetic load failed');
    final asset = AssetRecord.fromJson(record());
    return AssetLocationPage(
      [AssetLocationEntry(asset, label)],
      more ? offset + 50 : null,
      warrantyPage: warranty.isEmpty
          ? null
          : AssetWarrantyPage.fromJson(
              warrantyFixture(),
              offset: 0,
              warranty: warranty,
              asOf: asOf,
            ),
    );
  }

  @override
  Future<AssetLocation> readLocation(String id) async {
    reads++;
    return AssetLocation(id: id, version: 3, location: label);
  }

  @override
  Future<AssetLocation> updateLocation(
    AssetLocation original,
    String? location,
  ) async {
    locationWrites++;
    label = location;
    return AssetLocation(
      id: original.id,
      version: original.version + 1,
      location: location,
    );
  }

  @override
  Future<AssetWarrantyPage> listWarranty({
    required String query,
    required String status,
    String category = '',
    required String warranty,
    String asOf = '',
    required int offset,
  }) => throw StateError('Location filters must not be bypassed');
}

Future<void> openLocation(
  WidgetTester tester,
  LocationStore store, {
  bool enabled = true,
}) async {
  tester.view.physicalSize = const Size(1100, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: AssetsPage(
        store: store,
        enableAssetLocation: enabled,
        enableAssetDates: true,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> selectLocation(WidgetTester tester, String label) async {
  final dropdown = find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        widget.decoration.labelText == 'Location filter',
  );
  if (dropdown.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      dropdown,
      350,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'disabled capability keeps legacy list and hides location controls',
    (tester) async {
      final source = LocationStore();
      await openLocation(tester, source, enabled: false);
      expect(source.locationCalls, isEmpty);
      expect(source.calls, ['||0']);
      expect(find.text('Edit location'), findsNothing);
      expect(find.text('Location filter'), findsNothing);
    },
  );
  testWidgets(
    'exact filter applies explicitly, resets page and refresh retains last applied values',
    (tester) async {
      final source = LocationStore()..more = true;
      await openLocation(tester, source);
      final next = find.text('Next page');
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(source.locationCalls.last['offset'], 50);
      await selectLocation(tester, 'Exact location');
      final field = find.widgetWithText(TextField, 'Exact location');
      await tester.ensureVisible(field);
      await tester.enterText(field, ' Room %_ ');
      expect(source.locationCalls.last['offset'], 50);
      final apply = find.text('Apply filters');
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(source.locationCalls.last['offset'], 0);
      expect(source.locationCalls.last['location'], 'Room %_');
      await tester.ensureVisible(field);
      await tester.enterText(field, 'Unapplied');
      final refresh = find.text('Refresh inventory');
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(source.locationCalls.last['location'], 'Room %_');
      expect(source.calls, isEmpty);
    },
  );
  testWidgets(
    'unknown location differs from all, and load failure retains last successful rows',
    (tester) async {
      final source = LocationStore();
      await openLocation(tester, source);
      await selectLocation(tester, 'Unknown location');
      final apply = find.text('Apply filters');
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(source.locationCalls.last['mode'], 'unknown');
      expect(source.locationCalls.last['location'], isNull);
      source.fail = true;
      await tester.tap(find.text('Refresh inventory'));
      await tester.pumpAndSettle();
      expect(find.textContaining('may be stale'), findsOneWidget);
      expect(find.text('Laptop'), findsOneWidget);
    },
  );
  testWidgets(
    'location and warranty filters stay combined on Apply and Refresh',
    (tester) async {
      final source = LocationStore();
      await openLocation(tester, source);
      await selectLocation(tester, 'Exact location');
      final label = find.widgetWithText(TextField, 'Exact location');
      await tester.ensureVisible(label);
      await tester.enterText(label, 'Office');
      final warranty = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButtonFormField<String> &&
            widget.decoration.labelText == 'Warranty filter (UTC)',
      );
      await tester.ensureVisible(warranty);
      await tester.tap(warranty);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expiring within 30 days').last);
      await tester.pumpAndSettle();
      expect(source.locationCalls, hasLength(1));
      final apply = find.text('Apply filters');
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(source.locationCalls.last['location'], 'Office');
      expect(source.locationCalls.last['warranty'], 'expiring_soon');
      expect(find.textContaining('Applied warranty:'), findsOneWidget);
      await tester.tap(find.text('Refresh inventory'));
      await tester.pumpAndSettle();
      expect(source.locationCalls.last['location'], 'Office');
      expect(source.locationCalls.last['warranty'], 'expiring_soon');
      expect(source.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('location edit reads a fresh version then reloads after save', (
    tester,
  ) async {
    final source = LocationStore();
    await openLocation(tester, source);
    final edit = find.text('Edit location');
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(source.reads, 1);
    await tester.enterText(find.byType(TextField), 'Warehouse');
    await tester.tap(find.text('Save location'));
    await tester.pumpAndSettle();
    expect(source.label, 'Warehouse');
    expect(source.locationWrites, 1);
    expect(source.locationCalls, hasLength(2));
  });
  testWidgets(
    'blank exact error is inline and never requests unknown results',
    (tester) async {
      final source = LocationStore();
      await openLocation(tester, source);
      await selectLocation(tester, 'Exact location');
      final calls = source.locationCalls.length;
      await tester.ensureVisible(find.text('Apply filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextField, 'Exact location');
      expect(
        tester.widget<TextField>(field).decoration!.errorText,
        'Enter a location (1-120 characters), or select Unknown location.',
      );
      expect(source.locationCalls.length, calls);
      await tester.enterText(field, 'Office');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).decoration!.errorText, isNull);
      await tester.enterText(field, '');
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      await selectLocation(tester, 'Unknown location');
      await tester.ensureVisible(find.text('Apply filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      expect(source.locationCalls.last['mode'], 'unknown');
      expect(source.locationCalls.last['location'], isNull);
    },
  );

  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('enabled location controls at $width and text 200%', (
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
            child: AssetsPage(
              store: LocationStore(),
              enableAssetLocation: true,
              enableAssetDates: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await selectLocation(tester, 'Exact location');
      final field = find.widgetWithText(TextField, 'Exact location');
      await tester.ensureVisible(field);
      await tester.enterText(field, '');
      await tester.ensureVisible(find.text('Apply filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(field);
      expect(tester.widget<TextField>(field).decoration!.errorText, isNotNull);
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
      if (directory != null)
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '$directory/location-inventory-${width.toInt()}-200.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
    });
  }
}

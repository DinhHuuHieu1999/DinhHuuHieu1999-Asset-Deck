import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:asset_desk/assets_page.dart';

import 'assets_page_test.dart' show FakeStore;
import 'asset_desk_app_test.dart' show FakeSession;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset.dart';
import 'package:asset_desk/api/asset_dates.dart';
import 'package:asset_desk/api/asset_details.dart';
import 'package:asset_desk/api/asset_location.dart';
import 'package:asset_desk/asset_details_page.dart';

import 'asset_test.dart' show record;

class Dates implements AssetDatesSource {
  int reads = 0;
  Future<AssetDates>? pending;
  int version = 1;
  String? responseId;
  @override
  Future<AssetDates> readDates(String id) {
    reads++;
    return pending ??
        Future.value(
          AssetDates(
            id: responseId ?? id,
            version: version,
            input: const AssetDatesInput(
              purchasedOn: '2024-02-29',
              warrantyExpiresOn: null,
            ),
          ),
        );
  }

  @override
  Future<AssetDates> updateDates(AssetDates original, AssetDatesInput input) =>
      throw StateError('No writes');
}

class Location implements AssetLocationSource {
  int reads = 0;
  int version = 1;
  String? responseId;
  @override
  Future<AssetLocation> readLocation(String id) async {
    reads++;
    return AssetLocation(
      id: responseId ?? id,
      version: version,
      location: 'Room %_1',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected operation');
}

void main() {
  final asset = AssetRecord.fromJson(record());
  test('disabled capabilities do not read', () async {
    final value = await AssetDetailsSnapshot.load(asset);
    expect(value.dates, isNull);
    expect(value.location, isNull);
  });
  test('reads matching dates and literal location once', () async {
    final dates = Dates();
    final location = Location();
    final value = await AssetDetailsSnapshot.load(
      asset,
      datesSource: dates,
      locationSource: location,
    );
    expect(value.dates!.input.purchasedOn, '2024-02-29');
    expect(value.location!.location, 'Room %_1');
    expect([dates.reads, location.reads], [1, 1]);
  });
  test('version mismatch fails before another read', () async {
    final dates = Dates()..version = 2;
    final location = Location();
    await expectLater(
      AssetDetailsSnapshot.load(
        asset,
        datesSource: dates,
        locationSource: location,
      ),
      throwsA(isA<Exception>()),
    );
    expect(location.reads, 0);
  });
  test('wrong date identity fails closed', () async {
    final dates = Dates()..responseId = AssetRecord.fromJson(record(1)).id;
    await expectLater(
      AssetDetailsSnapshot.load(asset, datesSource: dates),
      throwsA(isA<Exception>()),
    );
  });
  for (final mismatch in ['identity', 'version']) {
    test('location $mismatch mismatch rejects the entire snapshot', () async {
      final location = Location();
      if (mismatch == 'identity') {
        location.responseId = AssetRecord.fromJson(record(1)).id;
      } else {
        location.version = 2;
      }
      await expectLater(
        AssetDetailsSnapshot.load(
          asset,
          datesSource: Dates(),
          locationSource: location,
        ),
        throwsA(isA<Exception>()),
      );
    });
  }
  test('invalidated context prevents subsequent reads', () async {
    final completer = Completer<AssetDates>();
    final dates = Dates()..pending = completer.future;
    final location = Location();
    var current = true;
    final result = AssetDetailsSnapshot.load(
      asset,
      datesSource: dates,
      locationSource: location,
      isCurrent: () => current,
    );
    final assertion = expectLater(result, throwsA(isA<Exception>()));
    current = false;
    completer.complete(
      AssetDates(
        id: asset.id,
        version: 1,
        input: const AssetDatesInput(
          purchasedOn: null,
          warrantyExpiresOn: null,
        ),
      ),
    );
    await assertion;
    expect(location.reads, 0);
  });
  testWidgets(
    'details label snapshot and disabled values without write actions',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: AssetDetailsPage(record: asset)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('not a live record'), findsOneWidget);
      expect(find.text('Laptop'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Location'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Not enabled'), findsWidgets);
      expect(find.text('Save'), findsNothing);
    },
  );
  testWidgets('failed verification does not expose partially verified dates', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AssetDetailsPage(
          record: asset,
          datesSource: Dates()..version = 2,
          locationSource: Location(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not verify'), findsOneWidget);
    expect(find.text('2024-02-29'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Purchase date'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Not verified'), findsWidgets);
  });
  testWidgets(
    'session change clears snapshot and rejects late optional reads',
    (tester) async {
      final session = FakeSession();
      final pending = Completer<AssetDates>();
      final location = Location();
      await tester.pumpWidget(
        MaterialApp(
          home: AssetDetailsPage(
            record: asset,
            session: session,
            datesSource: Dates()..pending = pending.future,
            locationSource: location,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Laptop'), findsOneWidget);
      session.signOut();
      await tester.pump();
      pending.complete(
        AssetDates(
          id: asset.id,
          version: 1,
          input: const AssetDatesInput(
            purchasedOn: '2024-02-29',
            warrantyExpiresOn: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Laptop'), findsNothing);
      expect(find.textContaining('Session changed'), findsOneWidget);
      expect(location.reads, 0);
      session.close();
    },
  );
  testWidgets(
    'Back preserves applied filters and unsent search without reload',
    (tester) async {
      final store = FakeStore();
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: AssetsPage(store: store)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'applied');
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'unsent draft');
      final calls = List<String>.of(store.calls);
      await tester.scrollUntilVisible(
        find.text('View details'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('View details'));
      await tester.pumpAndSettle();
      expect(find.text('Asset details'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(store.calls, calls);
      expect(store.writes, 0);
      expect(find.text('unsent draft'), findsOneWidget);
      expect(find.textContaining('Applied search: applied;'), findsOneWidget);
    },
  );
  testWidgets('explicit null dates mean Unknown', (tester) async {
    final dates = Dates()
      ..pending = Future.value(
        AssetDates(
          id: asset.id,
          version: 1,
          input: const AssetDatesInput(
            purchasedOn: null,
            warrantyExpiresOn: null,
          ),
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: AssetDetailsPage(record: asset, datesSource: dates),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Purchase date'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Unknown'), findsWidgets);
    expect(find.text('Not verified'), findsNothing);
    expect(find.textContaining('Could not verify'), findsNothing);
  });
  testWidgets('replacement discards old request before location read', (
    tester,
  ) async {
    final pending = Completer<AssetDates>();
    final oldLocation = Location();
    await tester.pumpWidget(
      MaterialApp(
        home: AssetDetailsPage(
          record: asset,
          datesSource: Dates()..pending = pending.future,
          locationSource: oldLocation,
        ),
      ),
    );
    await tester.pump();
    final replacement = AssetRecord.fromJson(
      record(1)..['name'] = 'Replacement asset',
    );
    final newLocation = Location();
    await tester.pumpWidget(
      MaterialApp(
        home: AssetDetailsPage(
          record: replacement,
          datesSource: Dates(),
          locationSource: newLocation,
        ),
      ),
    );
    await tester.pumpAndSettle();
    pending.complete(
      AssetDates(
        id: asset.id,
        version: 1,
        input: const AssetDatesInput(
          purchasedOn: null,
          warrantyExpiresOn: null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Replacement asset'), findsOneWidget);
    expect(find.text('Laptop'), findsNothing);
    expect(oldLocation.reads, 0);
    expect(newLocation.reads, 1);
    expect(find.textContaining('Could not verify'), findsNothing);
  });
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('details render at $width and text 200%', (tester) async {
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
              record: asset,
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
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('inventory details actions at width $width and text 200%', (
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
      await tester.scrollUntilVisible(
        find.text('Edit asset'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('View details'), findsOneWidget);
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
            '$directory/inventory-card-${width.toInt()}-200.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:asset_desk/assets_page.dart';

import 'asset_location_page_test.dart' show LocationStore;
import 'asset_desk_app_test.dart' show FakeSession;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/location_overview_page.dart';
import 'package:asset_desk/api/asset_location_overview.dart';
import 'package:asset_desk/api/asset_store.dart';

class Source implements AssetLocationOverviewSource {
  int reads = 0;
  Future<AssetLocationOverview> Function()? load;
  @override
  Future<AssetLocationOverview> locationOverview() async {
    reads++;
    if (load != null) return load!();
    return AssetLocationOverview.fromJson({
      'complete': true,
      'total': 3,
      'unknown': 1,
      'locations': [
        {'location': 'Room %_1', 'count': 2},
      ],
    });
  }
}

class NavigationSource extends LocationStore
    implements AssetLocationOverviewSource {
  @override
  Future<AssetLocationOverview> locationOverview() =>
      Source().locationOverview();
}

class SessionSource extends FakeSession implements AssetLocationOverviewSource {
  final pending = Completer<AssetLocationOverview>();
  @override
  Future<AssetLocationOverview> locationOverview() => pending.future;
}

void main() {
  testWidgets(
    'shows all counts and refresh failure retains explicit stale result',
    (tester) async {
      final source = Source();
      await tester.pumpWidget(
        MaterialApp(home: LocationOverviewPage(source: source)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Total assets: 3'), findsOneWidget);
      expect(find.text('Room %_1: 2'), findsOneWidget);
      source.load = () async =>
          throw const AssetFailure('Synthetic unavailable');
      await tester.tap(find.text('Refresh location overview'));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic unavailable'), findsOneWidget);
      expect(
        find.text(
          'Counts below are from the last successful load and may be outdated.',
        ),
        findsOneWidget,
      );
      expect(find.text('Total assets: 3'), findsOneWidget);
      expect(source.reads, 2);
    },
  );
  testWidgets('loading is single flight and no auto retry', (tester) async {
    final pending = Completer<AssetLocationOverview>();
    final source = Source()..load = (() => pending.future);
    await tester.pumpWidget(
      MaterialApp(home: LocationOverviewPage(source: source)),
    );
    await tester.pump();
    await tester.tap(find.text('Refresh location overview'));
    await tester.pump();
    expect(source.reads, 1);
    pending.completeError(const AssetFailure('Synthetic unavailable'));
    await tester.pumpAndSettle();
    expect(source.reads, 1);
  });
  for (final label in <String?>[null, 'Room %_1']) {
    testWidgets('selection returns exact bucket $label', (tester) async {
      LocationOverviewSelection? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await Navigator.of(context)
                    .push<LocationOverviewSelection>(
                      MaterialPageRoute(
                        builder: (_) => LocationOverviewPage(source: Source()),
                      ),
                    );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(label == null ? 'Unknown location: 1' : 'Room %_1: 2'),
      );
      await tester.pumpAndSettle();
      expect(selected, isNotNull);
      expect(selected!.location, label);
    });
  }

  testWidgets('session change clears counts and rejects late response', (
    tester,
  ) async {
    final source = SessionSource();
    addTearDown(source.close);
    await tester.pumpWidget(
      MaterialApp(home: LocationOverviewPage(source: source)),
    );
    await tester.pump();
    source.signOut();
    await tester.pump();
    source.pending.complete(await Source().locationOverview());
    await tester.pumpAndSettle();
    expect(find.text('Total assets: 3'), findsNothing);
    expect(
      find.text('Session changed. Return to inventory and sign in again.'),
      findsOneWidget,
    );
  });
  for (final label in <String?>[null, 'Room %_1']) {
    testWidgets('inventory navigation replaces filters for $label', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = NavigationSource();
      await tester.pumpWidget(
        MaterialApp(home: AssetsPage(store: source, enableAssetLocation: true)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search assets'),
        'old search',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Category filter'),
        'old category',
      );
      await tester.ensureVisible(find.text('Location overview'));
      await tester.tap(find.text('Location overview'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(label == null ? 'Unknown location: 1' : 'Room %_1: 2'),
      );
      await tester.pumpAndSettle();
      expect(source.locationCalls.last, {
        'q': '',
        'status': '',
        'category': '',
        'offset': 0,
        'mode': label == null ? 'unknown' : 'exact',
        'location': label,
        'warranty': '',
        'asOf': '',
      });
    });
  }
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('location overview render $width at 200%', (tester) async {
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final font = Platform.environment['ASSET_DESK_UI_CAPTURE_FONT'];
      if (font != null) {
        final loader = FontLoader('Capture');
        loader.addFont(
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
            child: LocationOverviewPage(source: Source()),
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
            '$directory/location-overview-${width.toInt()}-200.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}

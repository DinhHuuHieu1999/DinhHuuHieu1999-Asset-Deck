import 'package:asset_desk/asset_desk_app.dart';

import 'asset_desk_app_test.dart' show FakeSession;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:asset_desk/api/asset_warranty_overview.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:asset_desk/assets_page.dart';
import 'package:asset_desk/warranty_overview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'asset_warranty_overview_test.dart' show warrantyOverviewFixture;
import 'assets_page_test.dart' show FakeStore;

class WarrantyOverviewStore extends FakeStore
    implements AssetWarrantyOverviewSource {
  int reads = 0;
  Future<AssetWarrantyOverview> Function()? load;
  @override
  Future<AssetWarrantyOverview> warrantyOverview({String asOf = ''}) async {
    reads++;
    return load == null
        ? AssetWarrantyOverview.fromJson(warrantyOverviewFixture())
        : await load!();
  }
}

class WarrantySession extends FakeSession
    implements AssetWarrantyOverviewSource {
  Completer<AssetWarrantyOverview>? pending;
  @override
  Future<AssetWarrantyOverview> warrantyOverview({String asOf = ''}) async =>
      pending == null
      ? AssetWarrantyOverview.fromJson(warrantyOverviewFixture())
      : pending!.future;
}

void main() {
  testWidgets('valid empty inventory displays zero buckets, not an error', (
    tester,
  ) async {
    final store = WarrantyOverviewStore()
      ..load = (() async => AssetWarrantyOverview.fromJson({
        ...warrantyOverviewFixture(),
        'total': 0,
        'expired': 0,
        'expiringSoon': 0,
        'later': 0,
        'unknown': 0,
      }));
    await tester.pumpWidget(
      MaterialApp(home: WarrantyOverviewPage(source: store)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Total assets: 0'), findsOneWidget);
    expect(find.text('No assets in your inventory.'), findsOneWidget);
    expect(find.text('Expired: 0'), findsOneWidget);
    expect(find.text('Expiring within 30 days: 0'), findsOneWidget);
    expect(find.text('Later: 0'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Unknown warranty date: 0'), 150);
    expect(find.text('Unknown warranty date: 0'), findsOneWidget);
    expect(find.textContaining('last successful load'), findsNothing);
  });
  testWidgets('unexpected failure does not reveal internal exception text', (
    tester,
  ) async {
    final store = WarrantyOverviewStore()
      ..load = (() async => throw StateError('private synthetic diagnostic'));
    await tester.pumpWidget(
      MaterialApp(home: WarrantyOverviewPage(source: store)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load warranty overview.'), findsOneWidget);
    expect(find.textContaining('private synthetic diagnostic'), findsNothing);
    expect(find.textContaining('Total assets:'), findsNothing);
    expect(find.text('No assets in your inventory.'), findsNothing);
  });

  for (final pendingResponse in [false, true]) {
    testWidgets(
      'root sign-out removes private overview, pending=$pendingResponse',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final session = WarrantySession();
        await session.login('synthetic', 'synthetic');
        if (pendingResponse)
          session.pending = Completer<AssetWarrantyOverview>();
        await tester.pumpWidget(
          AssetDeskApp(session: session, enableAssetDates: true),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(OutlinedButton, 'Warranty overview'),
        );
        if (pendingResponse) {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
        } else {
          await tester.pumpAndSettle();
          expect(find.text('Total assets: 57'), findsOneWidget);
        }
        session.signOut();
        await tester.pumpAndSettle();
        session.pending?.complete(
          AssetWarrantyOverview.fromJson(warrantyOverviewFixture()),
        );
        await tester.pumpAndSettle();
        expect(find.text('Warranty overview'), findsNothing);
        expect(find.textContaining('Total assets:'), findsNothing);
        expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('navigation requires dates flag and overview capability', (
    tester,
  ) async {
    final store = WarrantyOverviewStore();
    await tester.pumpWidget(MaterialApp(home: AssetsPage(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('Warranty overview'), findsNothing);
    expect(store.reads, 0);
    await tester.pumpWidget(
      MaterialApp(
        home: AssetsPage(
          key: UniqueKey(),
          store: FakeStore(),
          enableAssetDates: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Warranty overview'), findsNothing);
  });
  testWidgets('all four buckets and reference are displayed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: WarrantyOverviewPage(source: WarrantyOverviewStore())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Expired: 51'), findsOneWidget);
    expect(find.text('Expiring within 30 days: 2'), findsOneWidget);
    expect(find.text('Later: 3'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Unknown warranty date: 1'), 150);
    expect(find.text('Unknown warranty date: 1'), findsOneWidget);
    expect(
      find.textContaining('Unknown does not mean expired'),
      findsOneWidget,
    );
  });
  testWidgets('disposed pending request cannot update the page', (
    tester,
  ) async {
    final pending = Completer<AssetWarrantyOverview>();
    final store = WarrantyOverviewStore()..load = (() => pending.future);
    await tester.pumpWidget(
      MaterialApp(home: WarrantyOverviewPage(source: store)),
    );
    await tester.pump();
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    await tester.pumpWidget(const MaterialApp(home: Text('Signed out')));
    pending.complete(AssetWarrantyOverview.fromJson(warrantyOverviewFixture()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Total assets:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'explicit navigation preserves unapplied list draft without writes',
    (tester) async {
      final store = WarrantyOverviewStore();
      await tester.pumpWidget(
        MaterialApp(home: AssetsPage(store: store, enableAssetDates: true)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'draft');
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Warranty overview'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Total assets: 57'), findsOneWidget);
      expect(store.reads, 1);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('draft'), findsOneWidget);
      expect(store.writes, 0);
      expect(store.calls.length, 1);
    },
  );
  testWidgets(
    'refresh failure keeps counts with stale warning; retry succeeds',
    (tester) async {
      final store = WarrantyOverviewStore();
      await tester.pumpWidget(
        MaterialApp(home: WarrantyOverviewPage(source: store)),
      );
      await tester.pumpAndSettle();
      store.load = () async =>
          throw const AssetFailure('Overview unavailable', statusCode: 422);
      await tester.tap(find.text('Refresh warranty overview'));
      await tester.pumpAndSettle();
      expect(find.text('Total assets: 57'), findsOneWidget);
      expect(find.textContaining('last successful load'), findsOneWidget);
      expect(find.text('Overview unavailable'), findsOneWidget);
      store.load = null;
      await tester.tap(find.text('Refresh warranty overview'));
      await tester.pumpAndSettle();
      expect(find.textContaining('last successful load'), findsNothing);
      expect(store.reads, 3);
    },
  );
  testWidgets('initial failure never displays zero inventory', (tester) async {
    final store = WarrantyOverviewStore()
      ..load = (() async =>
          throw const AssetFailure('Please sign in again', statusCode: 401));
    await tester.pumpWidget(
      MaterialApp(home: WarrantyOverviewPage(source: store)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Please sign in again'), findsOneWidget);
    expect(find.textContaining('Total assets:'), findsNothing);
  });
  testWidgets('source replacement discards old pending response', (
    tester,
  ) async {
    final pending = Completer<AssetWarrantyOverview>();
    final old = WarrantyOverviewStore()..load = (() => pending.future);
    final next = WarrantyOverviewStore();
    await tester.pumpWidget(
      MaterialApp(home: WarrantyOverviewPage(source: old)),
    );
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(home: WarrantyOverviewPage(source: next)),
    );
    await tester.pumpAndSettle();
    pending.completeError(const AssetFailure('Old account error'));
    await tester.pumpAndSettle();
    expect(find.text('Total assets: 57'), findsOneWidget);
    expect(find.text('Old account error'), findsNothing);
  });
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('synthetic overview $width at text 200%', (tester) async {
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
            child: WarrantyOverviewPage(source: WarrantyOverviewStore()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Total assets: 57'), findsOneWidget);
      final dir = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
      if (dir != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$dir/warranty-overview-${width.toInt()}-200.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}

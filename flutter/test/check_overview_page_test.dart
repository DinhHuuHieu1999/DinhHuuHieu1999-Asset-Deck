import 'dart:async';

import 'asset_desk_app_test.dart' show FakeSession;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:asset_desk/api/asset.dart';
import 'package:asset_desk/api/asset_check.dart';
import 'package:asset_desk/assets_page.dart';

import 'asset_check_filter_test.dart' show CheckStore;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset_check_overview.dart';
import 'package:asset_desk/check_overview_page.dart';

class OverviewSource implements AssetCheckOverviewSource {
  final calls = <String>[];
  bool fail = false;
  @override
  Future<AssetCheckOverview> checkOverview({required String cutoff}) async {
    calls.add(cutoff);
    if (fail) throw StateError('synthetic');
    return AssetCheckOverview.fromJson({
      'complete': true,
      'cutoff': cutoff,
      'total': 6,
      'unknown': 1,
      'before': 2,
      'onOrAfter': 3,
    }, cutoff: cutoff);
  }
}

class OverviewStore extends CheckStore
    implements AssetCheckOverviewSource, AssetCheckOnOrAfterSource {
  final overview = OverviewSource();
  String? afterCutoff;
  String? afterQuery;
  @override
  Future<AssetCheckOverview> checkOverview({required String cutoff}) =>
      overview.checkOverview(cutoff: cutoff);
  @override
  Future<AssetCheckPage> listCheckedOnOrAfter({
    required String checkOnOrAfter,
    required String query,
    required String status,
    required int offset,
    String sort = 'updated_desc',
    String category = '',
    bool includeLocation = false,
    String locationMode = 'all',
    String? location,
    String warranty = '',
    String asOf = '',
  }) async {
    afterCutoff = checkOnOrAfter;
    afterQuery = query;
    return AssetCheckPage(AssetPage([], null));
  }
}

class OverviewSession extends FakeSession implements AssetCheckOverviewSource {
  final pending = Completer<AssetCheckOverview>();
  @override
  Future<AssetCheckOverview> checkOverview({required String cutoff}) =>
      pending.future;
}

void main() {
  testWidgets(
    'initial cutoff uses local calendar and format errors stay local',
    (tester) async {
      final source = OverviewSource();
      final before = DateTime.now().toIso8601String().substring(0, 10);
      await tester.pumpWidget(
        MaterialApp(home: CheckOverviewPage(source: source)),
      );
      await tester.pumpAndSettle();
      final after = DateTime.now().toIso8601String().substring(0, 10);
      expect([before, after], contains(source.calls.single));
      await tester.enterText(find.byType(TextField), '2024/02/29');
      await tester.tap(find.text('Apply cutoff'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter the cutoff date in YYYY-MM-DD format.'),
        findsOneWidget,
      );
      expect(source.calls, hasLength(1));
    },
  );

  testWidgets('session change rejects late private overview', (tester) async {
    final session = OverviewSession();
    await tester.pumpWidget(
      MaterialApp(home: CheckOverviewPage(source: session)),
    );
    await tester.pump();
    session.signOut();
    await tester.pump();
    session.pending.complete(
      await OverviewSource().checkOverview(cutoff: '2024-02-29'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Session changed'), findsOneWidget);
    expect(find.textContaining('Total assets:'), findsNothing);
    expect(find.text('View assets: Before cutoff'), findsNothing);
    session.close();
  });

  for (final mode in ['Unknown check date', 'Before cutoff']) {
    testWidgets('overview opens exact bucket $mode', (tester) async {
      final store = OverviewStore();
      await tester.pumpWidget(
        MaterialApp(home: AssetsPage(store: store, enableAssetCheck: true)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check-date overview'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '2024-02-29');
      await tester.tap(find.text('Apply cutoff'));
      await tester.pumpAndSettle();
      // A draft must not silently change the reference used by bucket selection.
      await tester.enterText(find.byType(TextField), '2025-01-01');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final target = find.text('View assets: $mode');
      await tester.scrollUntilVisible(
        target,
        250,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      if (mode == 'Before cutoff')
        expect(store.beforeCalls, ['2024-02-29']);
      else
        expect(store.uncheckedCalls, 1);
    });
  }
  testWidgets('overview Back preserves applied scope, sort and unsent draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = OverviewStore();
    await tester.pumpWidget(
      MaterialApp(home: AssetsPage(store: store, enableAssetCheck: true)),
    );
    await tester.pumpAndSettle();
    final search = find.widgetWithText(TextField, 'Search assets');
    await tester.enterText(search, 'Synthetic');
    final sort = find.byKey(const ValueKey('inventory-sort-updated_desc'));
    await tester.ensureVisible(sort);
    await tester.tap(sort);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name A-Z').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Apply filters'));
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    final calls = List<String>.of(store.calls);
    await tester.ensureVisible(search);
    await tester.enterText(search, 'Unsent draft');
    await tester.ensureVisible(find.text('Check-date overview'));
    await tester.tap(find.text('Check-date overview'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(store.calls, calls);
    expect(find.text('Unsent draft'), findsOneWidget);
    expect(find.text('Applied sort: Name A-Z'), findsOneWidget);
    expect(find.textContaining('Applied search: Synthetic;'), findsOneWidget);
    await tester.ensureVisible(find.text('Refresh inventory'));
    await tester.tap(find.text('Refresh inventory'));
    await tester.pumpAndSettle();
    expect(store.calls.last, 'Synthetic||0');
    expect(store.sorts.last, 'name_asc');
  });
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('overview render $width at 200 percent', (tester) async {
      tester.view.physicalSize = Size(width, 1100);
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
            child: CheckOverviewPage(source: OverviewSource()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
      Future<void> capture(String state) async {
        if (directory == null) return;
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '$directory/check-overview-${width.toInt()}-$state.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('top');
      await tester.scrollUntilVisible(
        find.text('View assets: On or after cutoff'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.takeException(), isNull);
      await capture('buckets');
    });
  }

  testWidgets(
    'overview drill-down pins inclusive scope across refresh and reset',
    (tester) async {
      final store = OverviewStore();
      await tester.pumpWidget(
        MaterialApp(home: AssetsPage(store: store, enableAssetCheck: true)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check-date overview'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '2024-02-29');
      await tester.tap(find.text('Apply cutoff'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '2025-01-01');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final target = find.text('View assets: On or after cutoff');
      await tester.scrollUntilVisible(
        target,
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(store.afterCutoff, '2024-02-29');
      expect(store.afterQuery, '');
      final refresh = find.text('Refresh inventory');
      await tester.scrollUntilVisible(
        refresh,
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        find.text('Applied check filter: On or after 2024-02-29'),
        findsOneWidget,
      );
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(store.afterCutoff, '2024-02-29');
      await tester.tap(find.text('Reset filters'));
      await tester.pumpAndSettle();
      expect(find.text('Applied check filter: All assets'), findsOneWidget);
    },
  );

  testWidgets('shows a complete partition and refresh uses applied cutoff', (
    tester,
  ) async {
    final source = OverviewSource();
    await tester.pumpWidget(
      MaterialApp(home: CheckOverviewPage(source: source)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Total assets: 6'), findsOneWidget);
    final initial = source.calls.single;
    await tester.enterText(find.byType(TextField), '2024-02-29');
    await tester.tap(find.text('Refresh check-date overview'));
    await tester.pumpAndSettle();
    expect(source.calls.last, initial);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '2024-02-29',
    );
    await tester.tap(find.text('Apply cutoff'));
    await tester.pumpAndSettle();
    expect(find.text('Applied cutoff: 2024-02-29'), findsOneWidget);
  });
  testWidgets('invalid cutoff and failed load retain labelled old counts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = OverviewSource();
    await tester.pumpWidget(
      MaterialApp(home: CheckOverviewPage(source: source)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2023-02-29');
    await tester.tap(find.text('Apply cutoff'));
    await tester.pumpAndSettle();
    expect(source.calls.length, 1);
    expect(
      find.text('This date does not exist. Check the day, month and year.'),
      findsOneWidget,
    );
    expect(find.text('Total assets: 6'), findsOneWidget);
    source.fail = true;
    await tester.tap(find.text('Refresh check-date overview'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load check-date overview.'), findsOneWidget);
    for (final bucket in [
      'Unknown check date',
      'Before cutoff',
      'On or after cutoff',
    ]) {
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'View assets: $bucket'),
      );
      expect(button.onPressed, isNull);
    }

    expect(
      find.text(
        'Counts below are from the last successful load and may be outdated.',
      ),
      findsOneWidget,
    );
  });
}

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:asset_desk/api/asset_warranty.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:asset_desk/assets_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'assets_page_test.dart' show FakeStore;
import 'asset_test.dart' show record;
import 'asset_warranty_test.dart' show warrantyFixture;

class WarrantyStore extends FakeStore implements AssetWarrantySource {
  final warrantyCalls = <Map<String, Object>>[];
  bool more = false;
  String today = '2026-10-26';
  AssetFailure? warrantyFailure;
  Completer<AssetWarrantyPage>? pending;
  @override
  Future<AssetWarrantyPage> listWarranty({
    String sort = 'updated_desc',
    required String query,
    required String status,
    String category = '',
    required String warranty,
    String asOf = '',
    required int offset,
  }) async {
    warrantyCalls.add({
      'sort': sort,
      'query': query,
      'status': status,
      'category': category,
      'warranty': warranty,
      'asOf': asOf,
      'offset': offset,
    });
    if (warrantyFailure != null) throw warrantyFailure!;
    if (pending != null) return pending!.future;
    final day = asOf.isEmpty ? today : asOf;
    final end = warranty == 'expired' ? '0001-01-01' : day;
    return AssetWarrantyPage.fromJson(
      warrantyFixture(
        filter: warranty,
        day: day,
        items: List.generate(
          more && offset == 0 ? 50 : 1,
          (i) => {
            ...record(i + offset),
            'name': 'Warranty item ${i + offset}',
            'purchasedOn': null,
            'warrantyExpiresOn': end,
          },
        ),
        next: more && offset == 0 ? 50 : null,
      ),
      warranty: warranty,
      asOf: asOf,
      offset: offset,
    );
  }
}

Future<void> openWarranty(
  WidgetTester tester,
  FakeStore store, {
  bool enabled = true,
}) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: AssetsPage(store: store, enableAssetDates: enabled),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> selectWarranty(WidgetTester tester, String label) async {
  final field = find.byType(DropdownButtonFormField<String>).last;
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> press(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label),
    500,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 150,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'requires flag and capability; selecting does not load until Apply',
    (tester) async {
      final store = WarrantyStore();
      await openWarranty(tester, store, enabled: false);
      expect(find.text('Warranty filter (UTC)'), findsNothing);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await openWarranty(tester, FakeStore());
      expect(find.text('Warranty filter (UTC)'), findsNothing);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await openWarranty(tester, store);
      expect(store.warrantyCalls, isEmpty);
      await selectWarranty(tester, 'Expired');
      expect(store.warrantyCalls, isEmpty);
      await press(tester, 'Apply filters');
      expect(store.warrantyCalls.single['warranty'], 'expired');
      expect(
        find.textContaining('Expired before 2026-10-26 UTC'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'intersects applied filters and refresh ignores unsubmitted edits',
    (tester) async {
      final store = WarrantyStore();
      await openWarranty(tester, store);
      await tester.enterText(find.byType(TextField).first, ' %_ ');
      await tester.enterText(find.byType(TextField).at(1), ' Network ');
      await selectWarranty(tester, 'Expiring within 30 days');
      await press(tester, 'Apply filters');
      expect(store.warrantyCalls.single, {
        'sort': 'updated_desc',
        'query': '%_',
        'category': 'Network',
        'status': '',
        'warranty': 'expiring_soon',
        'asOf': '',
        'offset': 0,
      });
      await selectWarranty(tester, 'Expired');
      store.today = '2026-10-27';
      await press(tester, 'Refresh inventory');
      expect(store.warrantyCalls.last['warranty'], 'expiring_soon');
      expect(store.warrantyCalls.last['asOf'], '');
      expect(
        find.textContaining('2026-10-27 UTC through 2026-11-26 inclusive'),
        findsOneWidget,
      );
      await selectWarranty(tester, 'All warranties');
      await press(tester, 'Apply filters');
      expect(store.calls.last, '%_||0');
      expect(find.textContaining('Applied warranty:'), findsNothing);
    },
  );
  testWidgets('next and previous preserve calendar; refresh resets it', (
    tester,
  ) async {
    final store = WarrantyStore()..more = true;
    await openWarranty(tester, store);
    await selectWarranty(tester, 'Expired');
    await press(tester, 'Apply filters');
    store.today = '2026-10-27';
    await press(tester, 'Next page');
    expect(store.warrantyCalls.last['asOf'], '2026-10-26');
    expect(store.warrantyCalls.last['offset'], 50);
    await press(tester, 'Previous page');
    expect(store.warrantyCalls.last['asOf'], '2026-10-26');
    expect(store.warrantyCalls.last['offset'], 0);
    await press(tester, 'Refresh inventory');
    expect(store.warrantyCalls.last['asOf'], '');
  });
  testWidgets(
    'failure preserves prior result and date without legacy fallback',
    (tester) async {
      final store = WarrantyStore();
      await openWarranty(tester, store);
      await selectWarranty(tester, 'Expired');
      await press(tester, 'Apply filters');
      final legacy = store.calls.length;
      store.warrantyFailure = const AssetFailure(
        'Synthetic refusal',
        statusCode: 503,
      );
      await selectWarranty(tester, 'Expiring within 30 days');
      await press(tester, 'Apply filters');
      expect(find.text('Synthetic refusal'), findsOneWidget);
      expect(find.textContaining('may be stale'), findsOneWidget);
      expect(
        find.textContaining('Expired before 2026-10-26 UTC'),
        findsOneWidget,
      );
      expect(store.calls.length, legacy);
    },
  );
  testWidgets('dispose ignores late warranty response', (tester) async {
    final store = WarrantyStore();
    await openWarranty(tester, store);
    await selectWarranty(tester, 'Expired');
    store.pending = Completer<AssetWarrantyPage>();
    await tester.tap(find.text('Apply filters'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: Text('Signed out')));
    store.pending!.complete(
      AssetWarrantyPage.fromJson(
        warrantyFixture(filter: 'expired', items: []),
        warranty: 'expired',
        asOf: '',
        offset: 0,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Applied warranty:'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('warranty inventory render $width at 200 percent', (
      tester,
    ) async {
      final font = Platform.environment['ASSET_DESK_UI_CAPTURE_FONT'];
      if (font != null) {
        final loader = FontLoader('Capture')
          ..addFont(
            Future.value(ByteData.sublistView(File(font).readAsBytesSync())),
          );
        await loader.load();
      }
      tester.view.physicalSize = Size(width, 1600);
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
            child: AssetsPage(store: WarrantyStore(), enableAssetDates: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await selectWarranty(tester, 'Expiring within 30 days');
      await press(tester, 'Apply filters');
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
      if (directory != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$directory/warranty-${width.toInt()}-200.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}

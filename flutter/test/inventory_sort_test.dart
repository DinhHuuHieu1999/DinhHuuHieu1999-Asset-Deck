import 'package:asset_desk/assets_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'warranty_overview_page_test.dart'
    show DrilldownWarrantyStore, LocationDrilldownStore;
import 'asset_warranty_page_test.dart' show press;

void main() {
  for (final location in [false, true]) {
    testWidgets(
      'warranty drilldown preserves applied sort, not draft; location=$location',
      (tester) async {
        final store = location
            ? LocationDrilldownStore()
            : DrilldownWarrantyStore();
        tester.view.physicalSize = const Size(1000, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: AssetsPage(
              store: store,
              enableAssetDates: true,
              enableAssetLocation: location,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('inventory-sort-updated_desc')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Name A-Z').last);
        await tester.pumpAndSettle();
        await press(tester, 'Apply filters');
        await tester.ensureVisible(
          find.byKey(const ValueKey('inventory-sort-name_asc')),
        );
        await tester.tap(find.byKey(const ValueKey('inventory-sort-name_asc')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Updated most recently').last);
        await tester.pumpAndSettle();
        // Back preserves the unsubmitted sort draft without issuing a list request.
        await tester.scrollUntilVisible(
          find.text('Warranty overview').hitTestable(),
          -250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Warranty overview'));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('inventory-sort-updated_desc')),
          findsOneWidget,
        );
        await tester.tap(find.text('Warranty overview'));
        await tester.pumpAndSettle();
        await press(tester, 'View expired assets');
        expect(store.warrantyCalls.last['sort'], 'name_asc');
        expect(store.warrantyCalls.last['asOf'], '2026-10-27');
        await press(tester, 'Refresh inventory');
        expect(store.warrantyCalls.last['sort'], 'name_asc');
        expect(store.warrantyCalls.last['asOf'], '2026-10-27');
        expect(store.writes, 0);
      },
    );
  }
}

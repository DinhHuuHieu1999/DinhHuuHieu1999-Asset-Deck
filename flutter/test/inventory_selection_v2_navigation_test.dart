import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset_location.dart';
import 'package:asset_desk/api/asset_selection_export_v2.dart';
import 'package:asset_desk/assets_page.dart';
import 'package:asset_desk/inventory_selection_export_v2_page.dart';
import 'package:asset_desk/inventory_inspection_page.dart';

import 'asset_check_filter_test.dart' show CheckStore;

class SelectionCheckStore extends CheckStore
    implements AssetLocationSource, AssetSelectionExportV2Source {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #listLocations)
      return Future.value(AssetLocationPage([], null));
    return super.noSuchMethod(invocation);
  }
}

void main() {
  for (final before in [false, true]) {
    testWidgets(
      'v2 snapshots applied check filter and preserves draft on Back: $before',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = SelectionCheckStore();
        await tester.pumpWidget(
          MaterialApp(
            home: AssetsPage(
              store: store,
              enableSelectionExportV2: true,
              enableSelectionExport: true,
              enableAssetCheck: true,
              enableAssetDates: true,
              enableAssetLocation: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> press(String label) async {
          await tester.scrollUntilVisible(
            find.text(label),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
        }

        await press(before ? 'Checked before' : 'Only unknown check dates');
        if (before)
          await tester.enterText(
            find.widgetWithText(TextField, 'Before date'),
            '2024-03-01',
          );
        await press('Apply filters');
        if (before)
          await tester.enterText(
            find.widgetWithText(TextField, 'Before date'),
            '2025-01-01',
          );
        await press('Export matching assets JSON v2 with check dates');
        final page = tester.widget<InventorySelectionExportV2Page>(
          find.byType(InventorySelectionExportV2Page),
        );
        expect(
          page.scope.check,
          before
              ? {'mode': 'before', 'cutoff': '2024-03-01'}
              : {'mode': 'unknown'},
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        if (before) expect(find.text('2025-01-01'), findsOneWidget);
        await press('Inspect selection JSON v2 (no import)');
        expect(
          tester
              .widget<InventoryInspectionPage>(
                find.byType(InventoryInspectionPage),
              )
              .selectionV2,
          true,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(AssetsPage), findsOneWidget);
      },
    );
  }
  testWidgets('v2 default-off hides both new routes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AssetsPage(
          store: SelectionCheckStore(),
          enableSelectionExport: true,
          enableAssetCheck: true,
          enableAssetDates: true,
          enableAssetLocation: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Export matching assets JSON v2 with check dates'),
      findsNothing,
    );
    expect(find.text('Inspect selection JSON v2 (no import)'), findsNothing);
  });
}

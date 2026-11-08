import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset_import_v3.dart';
import 'package:asset_desk/api/asset_session.dart';
import 'package:asset_desk/assets_page.dart';

import 'asset_desk_app_test.dart' show FakeSession;

class V3Session extends FakeSession implements AssetImportV3Source {
  int imports = 0;
  @override
  Future<AssetImportV3Receipt> importInventoryV3(
    AssetImportV3Draft draft, {
    required int sessionRevision,
  }) async {
    imports++;
    throw StateError('No writes expected');
  }
}

void main() {
  testWidgets('signed-out v3 capability cannot expose import entry', (
    tester,
  ) async {
    final session = V3Session();
    addTearDown(session.close);
    await tester.pumpWidget(
      MaterialApp(
        home: AssetsPage(
          store: session,
          enableInventoryImportV3: true,
          enableInventoryImport: true,
          enableAssetDates: true,
          enableAssetLocation: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Import inventory JSON v3 (add-only, dates and location)'),
      findsNothing,
    );
    expect(session.imports, 0);
  });

  for (final flags in [
    [false, true, true, true],
    [true, false, true, true],
    [true, true, false, true],
    [true, true, true, false],
    [true, true, true, true],
  ]) {
    testWidgets('v3 requires all client flags $flags', (tester) async {
      final session = V3Session()
        ..account = const AssetAccount(
          id: 'aaaaaaaaaaaaaaaaaaaaaaaa',
          name: 'Synthetic',
        );
      addTearDown(session.close);
      await tester.pumpWidget(
        MaterialApp(
          home: AssetsPage(
            store: session,
            enableInventoryImportV3: flags[0],
            enableInventoryImport: flags[1],
            enableAssetDates: flags[2],
            enableAssetLocation: flags[3],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final entry = find.text(
        'Import inventory JSON v3 (add-only, dates and location)',
      );
      final enabled = flags.every((v) => v);
      expect(entry, enabled ? findsOneWidget : findsNothing);
      if (enabled) {
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.text('Import inventory JSON v3'), findsOneWidget);
      }
      expect(session.imports, 0);
    });
  }
  testWidgets('legacy source cannot expose v3 even with all flags', (
    tester,
  ) async {
    final session = FakeSession()
      ..account = const AssetAccount(
        id: 'aaaaaaaaaaaaaaaaaaaaaaaa',
        name: 'Synthetic',
      );
    addTearDown(session.close);
    await tester.pumpWidget(
      MaterialApp(
        home: AssetsPage(
          store: session,
          enableInventoryImportV3: true,
          enableInventoryImport: true,
          enableAssetDates: true,
          enableAssetLocation: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Import inventory JSON v3 (add-only, dates and location)'),
      findsNothing,
    );
  });
}

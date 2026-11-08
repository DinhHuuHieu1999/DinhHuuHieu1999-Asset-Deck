import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset_import_v2.dart';
import 'package:asset_desk/api/asset_session.dart';
import 'package:asset_desk/assets_page.dart';

import 'asset_desk_app_test.dart' show FakeSession;

class V2Session extends FakeSession implements AssetImportV2Source {
  int imports = 0;
  @override
  Future<AssetImportV2Receipt> importInventoryV2(
    AssetImportV2Draft draft, {
    required int sessionRevision,
  }) async {
    imports++;
    throw StateError('No writes expected');
  }
}

void main() {
  testWidgets('signed-out v2 capability cannot expose import entry', (
    tester,
  ) async {
    final session = V2Session();
    addTearDown(session.close);
    await tester.pumpWidget(
      MaterialApp(
        home: AssetsPage(
          store: session,
          enableInventoryImportV2: true,
          enableInventoryImport: true,
          enableAssetDates: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Import inventory JSON v2 (add-only, with dates)'),
      findsNothing,
    );
    expect(session.imports, 0);
  });

  for (final flags in [
    [false, true, true],
    [true, false, true],
    [true, true, false],
    [true, true, true],
  ]) {
    testWidgets('v2 requires all client flags $flags', (tester) async {
      final session = V2Session()
        ..account = const AssetAccount(
          id: 'aaaaaaaaaaaaaaaaaaaaaaaa',
          name: 'Synthetic',
        );
      addTearDown(session.close);
      await tester.pumpWidget(
        MaterialApp(
          home: AssetsPage(
            store: session,
            enableInventoryImportV2: flags[0],
            enableInventoryImport: flags[1],
            enableAssetDates: flags[2],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final entry = find.text(
        'Import inventory JSON v2 (add-only, with dates)',
      );
      final enabled = flags.every((v) => v);
      expect(entry, enabled ? findsOneWidget : findsNothing);
      if (enabled) {
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.text('Import inventory JSON v2'), findsOneWidget);
      }
      expect(session.imports, 0);
    });
  }
  testWidgets('legacy source cannot expose v2 even with all flags', (
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
          enableInventoryImportV2: true,
          enableInventoryImport: true,
          enableAssetDates: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Import inventory JSON v2 (add-only, with dates)'),
      findsNothing,
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset_import_v4.dart';
import 'package:asset_desk/api/asset_session.dart';
import 'package:asset_desk/assets_page.dart';
import 'package:asset_desk/asset_desk_app.dart';

import 'asset_desk_app_test.dart' show FakeSession;

class V4Session extends FakeSession implements AssetImportV4Source {
  int imports = 0;
  @override
  Future<AssetImportV4Receipt> importInventoryV4(
    AssetImportV4Draft draft, {
    required int sessionRevision,
  }) async {
    imports++;
    throw StateError('No writes expected');
  }
}

void main() {
  testWidgets('signed-out v4 capability cannot expose import entry', (
    tester,
  ) async {
    final session = V4Session();
    addTearDown(session.close);
    await tester.pumpWidget(
      MaterialApp(
        home: AssetsPage(
          store: session,
          enableInventoryImportV4: true,
          enableInventoryImport: true,
          enableAssetDates: true,
          enableAssetLocation: true,
          enableAssetCheck: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Import inventory JSON v4 (add-only, with check dates)'),
      findsNothing,
    );
    expect(session.imports, 0);
  });

  for (final flags in [
    [false, true, true, true, true],
    [true, false, true, true, true],
    [true, true, false, true, true],
    [true, true, true, false, true],
    [true, true, true, true, false],
    [true, true, true, true, true],
  ]) {
    testWidgets('v4 requires all client flags $flags', (tester) async {
      final session = V4Session()
        ..account = const AssetAccount(
          id: 'aaaaaaaaaaaaaaaaaaaaaaaa',
          name: 'Synthetic',
        );
      addTearDown(session.close);
      await tester.pumpWidget(
        MaterialApp(
          home: AssetsPage(
            store: session,
            enableInventoryImportV4: flags[0],
            enableInventoryImport: flags[1],
            enableAssetDates: flags[2],
            enableAssetLocation: flags[3],
            enableAssetCheck: flags[4],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final entry = find.text(
        'Import inventory JSON v4 (add-only, with check dates)',
      );
      final enabled = flags.every((v) => v);
      expect(entry, enabled ? findsOneWidget : findsNothing);
      if (enabled) {
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.text('Import inventory JSON v4'), findsOneWidget);
      }
      expect(session.imports, 0);
    });
  }
  testWidgets('app forwards v4 flag and default stays disabled', (
    tester,
  ) async {
    final session = V4Session()
      ..account = const AssetAccount(
        id: 'aaaaaaaaaaaaaaaaaaaaaaaa',
        name: 'Synthetic',
      );
    addTearDown(session.close);
    Future<void> mount(bool enabled) async {
      await tester.pumpWidget(
        AssetDeskApp(
          session: session,
          enableInventoryImportV4: enabled,
          enableInventoryImport: true,
          enableAssetDates: true,
          enableAssetLocation: true,
          enableAssetCheck: true,
        ),
      );
      await tester.pumpAndSettle();
    }

    await mount(false);
    final entry = find.text(
      'Import inventory JSON v4 (add-only, with check dates)',
    );
    expect(entry, findsNothing);
    await mount(true);
    expect(entry, findsOneWidget);
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.text('Import inventory JSON v4'), findsOneWidget);
    expect(session.imports, 0);
  });
  testWidgets('legacy source cannot expose v4 even with all flags', (
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
          enableInventoryImportV4: true,
          enableInventoryImport: true,
          enableAssetDates: true,
          enableAssetLocation: true,
          enableAssetCheck: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Import inventory JSON v4 (add-only, with check dates)'),
      findsNothing,
    );
  });
}

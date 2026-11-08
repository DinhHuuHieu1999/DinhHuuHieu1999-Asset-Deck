import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:asset_desk/api/asset_export.dart';
import 'package:asset_desk/api/asset_session.dart';
import 'package:asset_desk/assets_page.dart';
import 'package:asset_desk/asset_desk_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'assets_page_test.dart' show FakeStore;
import 'asset_desk_app_test.dart' show FakeSession;

class ExportStore extends FakeStore implements AssetExportSource {
  ExportStore(this.snapshot);
  final AssetExport snapshot;
  int exports = 0;
  @override
  Future<AssetExport> exportInventory({
    required AssetExportDigest digest,
  }) async {
    exports++;
    return snapshot;
  }
}

class ExportSession extends FakeSession implements AssetExportSource {
  ExportSession(this.snapshot);
  final AssetExport snapshot;
  Completer<AssetExport>? pending;
  @override
  Future<AssetExport> exportInventory({
    required AssetExportDigest digest,
  }) async => pending == null ? snapshot : pending!.future;
}

void main() {
  late AssetExport snapshot;
  setUpAll(() async {
    final json = jsonDecode(
      File('test/fixtures/inventory-export-v1.json').readAsStringSync(),
    ) as Map<String, Object?>;
    snapshot = await AssetExport.parse(
      json,
      digest: (_) async => json['sha256']! as String,
    );
  });
  Future<void> size(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'export route leaves applied inventory filters and loaded page intact',
    (tester) async {
      await size(tester);
      final store = ExportStore(snapshot);
      await tester.pumpWidget(MaterialApp(home: AssetsPage(store: store)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '%_');
      await tester.enterText(
        find.widgetWithText(TextField, 'Category filter'),
        'network',
      );
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      final calls = List<String>.of(store.calls);
      await tester.tap(find.text('Export all inventory JSON'));
      await tester.pumpAndSettle();
      expect(store.exports, 0);
      await tester.tap(find.text('Prepare JSON'));
      await tester.pumpAndSettle();
      expect(store.exports, 1);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(store.calls, calls);
      expect(
        find.text('Applied search: %_; status: all; category: network'),
        findsOneWidget,
      );
      expect(store.writes, 0);
    },
  );
  for (final delayed in [false, true]) {
    testWidgets('session invalidation clears export route, delayed=$delayed', (
      tester,
    ) async {
      await size(tester);
      final session = ExportSession(snapshot)
        ..account = const AssetAccount(
          id: 'aaaaaaaaaaaaaaaaaaaaaaaa',
          name: 'Synthetic owner',
        );
      if (delayed) session.pending = Completer<AssetExport>();
      await tester.pumpWidget(AssetDeskApp(session: session));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export all inventory JSON'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prepare JSON'));
      if (delayed) {
        await tester.pump();
      } else {
        await tester.pumpAndSettle();
        expect(find.textContaining('Complete snapshot:'), findsOneWidget);
      }
      session.signOut();
      await tester.pumpAndSettle();
      session.pending?.complete(snapshot);
      await tester.pumpAndSettle();
      expect(find.textContaining('Complete snapshot:'), findsNothing);
      expect(find.text('Save JSON as... (Windows)'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

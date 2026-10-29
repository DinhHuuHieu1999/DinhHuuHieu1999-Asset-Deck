import 'dart:async';

import 'package:asset_desk/asset_desk_app.dart';

import 'asset_desk_app_test.dart' show FakeSession;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'assets_page_test.dart' show FakeStore;

import 'package:asset_desk/assets_page.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset_selection_export.dart';
import 'package:asset_desk/api/asset_export.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:asset_desk/inventory_export_files.dart';
import 'package:asset_desk/inventory_selection_export_page.dart';

import 'asset_selection_export_test.dart' show selectionFixture;

class Source implements AssetSelectionExportSource {
  Source(this.snapshot);
  final AssetSelectionExport snapshot;
  int calls = 0;
  bool fail = false;
  @override
  Future<AssetSelectionExport> exportSelection({
    required AssetSelectionScope scope,
    required AssetExportDigest digest,
  }) async {
    calls++;
    if (fail) throw const AssetFailure('Synthetic prepare failed');
    return snapshot;
  }
}

class Files implements InventorySelectionExportFiles {
  int saves = 0;
  bool saved = false;
  @override
  Future<String> digest(Uint8List bytes) async => 'a' * 64;
  @override
  Future<bool> saveSelection(AssetSelectionExport snapshot) async {
    saves++;
    return saved;
  }
}

class SelectionStore extends FakeStore implements AssetSelectionExportSource {
  @override
  Future<AssetSelectionExport> exportSelection({
    required AssetSelectionScope scope,
    required AssetExportDigest digest,
  }) => throw UnimplementedError();
}

class SelectionSession extends FakeSession
    implements AssetSelectionExportSource {
  Completer<AssetSelectionExport>? pending;
  AssetSelectionScope? requested;
  int reads = 0;
  Future<AssetSelectionExport> snapshot(AssetSelectionScope scope) async {
    final value = selectionFixture();
    final payload =
        jsonDecode(value['payload']! as String) as Map<String, Object?>;
    payload['filters'] = scope.filters;
    value['payload'] = jsonEncode(payload);
    return AssetSelectionExport.parse(value, digest: (_) async => 'a' * 64);
  }

  @override
  Future<AssetSelectionExport> exportSelection({
    required AssetSelectionScope scope,
    required AssetExportDigest digest,
  }) async {
    reads++;
    requested = scope;
    return pending == null ? snapshot(scope) : pending!.future;
  }
}

void main() {
  for (final pendingResponse in [false, true]) {
    testWidgets(
      'sign-out removes private selection and ignores late response: $pendingResponse',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final session = SelectionSession();
        await session.login('synthetic', 'synthetic');
        if (pendingResponse)
          session.pending = Completer<AssetSelectionExport>();
        await tester.pumpWidget(
          AssetDeskApp(
            session: session,
            enableAssetDates: true,
            enableAssetLocation: true,
            enableSelectionExport: true,
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Export matching assets JSON'));
        await tester.tap(find.text('Export matching assets JSON'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Prepare selection JSON'),
          200,
        );
        await tester.tap(find.text('Prepare selection JSON'));
        if (pendingResponse) {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
        } else {
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Matching selection: 1 asset'),
            150,
          );
          expect(find.text('Matching selection: 1 asset'), findsOneWidget);
        }
        expect(session.reads, 1);
        session.signOut();
        await tester.pumpAndSettle();
        if (pendingResponse)
          session.pending!.complete(await session.snapshot(session.requested!));
        await tester.pumpAndSettle();
        expect(find.byType(InventorySelectionExportPage), findsNothing);
        expect(find.textContaining('Checksum matches'), findsNothing);
        expect(find.textContaining('Matching selection:'), findsNothing);
        expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
        expect(session.reads, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final config in [
    (false, true, true, true),
    (true, false, true, true),
    (true, true, false, true),
    (true, true, true, false),
  ]) {
    testWidgets(
      'selection navigation requires all opt-ins and source capability: $config',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: AssetsPage(
              store: config.$4 ? SelectionStore() : FakeStore(),
              enableSelectionExport: config.$1,
              enableAssetDates: config.$2,
              enableAssetLocation: config.$3,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Export matching assets JSON'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('selection render $width at 200 percent', (tester) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final font = Platform.environment['ASSET_DESK_UI_CAPTURE_FONT'];
      if (font != null) {
        final loader = FontLoader('SelectionCapture')
          ..addFont(
            Future.value(ByteData.sublistView(File(font).readAsBytesSync())),
          );
        await loader.load();
      }
      final snapshot = await AssetSelectionExport.parse(
        selectionFixture(),
        digest: (_) async => 'a' * 64,
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            fontFamily: font == null ? null : 'SelectionCapture',
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: key,
            child: InventorySelectionExportPage(
              source: Source(snapshot),
              files: Files(),
              scope: snapshot.scope,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prepare selection JSON'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final dir = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
      if (dir != null)
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$dir/selection-${width.toInt()}-200.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
    });
  }

  testWidgets(
    'navigation snapshots applied filters, not draft controls; Back preserves inventory',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = SelectionStore();
      await tester.pumpWidget(
        MaterialApp(
          home: AssetsPage(
            store: store,
            enableSelectionExport: true,
            enableAssetDates: true,
            enableAssetLocation: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '%_');
      await tester.ensureVisible(find.text('Apply filters'));
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'UNAPPLIED');
      await tester.ensureVisible(find.text('Export matching assets JSON'));
      await tester.tap(find.text('Export matching assets JSON'));
      await tester.pumpAndSettle();
      final page = tester.widget<InventorySelectionExportPage>(
        find.byType(InventorySelectionExportPage),
      );
      expect(page.scope.filters['q'], '%_');
      expect(page.scope.filters['sort'], 'updated_desc');
      expect(store.calls.last, '%_||0');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(AssetsPage), findsOneWidget);
      expect(find.text('UNAPPLIED'), findsOneWidget);
      expect(store.calls.length, 2);
    },
  );

  testWidgets(
    'explicit Prepare, Cancel preserves result, save and failed Prepare are clear',
    (tester) async {
      final value = selectionFixture();
      final snapshot = await AssetSelectionExport.parse(
        value,
        digest: (_) async => 'a' * 64,
      );
      final source = Source(snapshot), files = Files();
      final payload =
          jsonDecode(value['payload']! as String) as Map<String, Object?>;
      final scope = AssetSelectionScope.fromJson(
        payload['filters']! as Map<String, Object?>,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: InventorySelectionExportPage(
            source: source,
            files: files,
            scope: scope,
          ),
        ),
      );
      expect(source.calls, 0);
      final prepare = find.text('Prepare selection JSON');
      await tester.scrollUntilVisible(prepare, 250);
      await tester.tap(prepare);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Matching selection: 1 asset'),
        150,
      );
      expect(find.text('Matching selection: 1 asset'), findsOneWidget);
      final save = find.text('Save selection JSON as... (Windows)');
      await tester.scrollUntilVisible(save, 250);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(files.saves, 1);
      expect(
        find.text('Save canceled. Prepared selection retained.'),
        findsOneWidget,
      );
      expect(find.text('Matching selection: 1 asset'), findsOneWidget);
      files.saved = true;
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Selection JSON saved.'), findsOneWidget);
      source.fail = true;
      await tester.scrollUntilVisible(prepare, -250);
      await tester.tap(prepare);
      await tester.pumpAndSettle();
      expect(find.text('Matching selection: 1 asset'), findsNothing);
      expect(find.textContaining('Checksum matches'), findsNothing);
      expect(find.text('Synthetic prepare failed'), findsOneWidget);
    },
  );
}

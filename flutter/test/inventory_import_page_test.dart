import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset_import.dart';
import 'package:asset_desk/api/asset_session.dart';
import 'package:asset_desk/inventory_import_page.dart';

import 'inventory_inspection_page_test.dart' show Files;

import 'package:asset_desk/inventory_recovery_files.dart';
import 'package:asset_desk/api/asset_import_recovery.dart';

class Session implements AssetSession {
  final changes = StreamController<int>.broadcast();
  @override
  AssetAccount? get account =>
      const AssetAccount(id: 'aaaaaaaaaaaaaaaaaaaaaaaa', name: 'Synthetic');
  @override
  int get sessionRevision => 1;
  @override
  Stream<int> get sessionChanges => changes.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Source implements AssetImportSource {
  int calls = 0;
  bool fail = false;
  final drafts = <AssetImportDraft>[];
  @override
  Future<AssetImportReceipt> importInventory(
    AssetImportDraft draft, {
    required int sessionRevision,
  }) async {
    calls++;
    drafts.add(draft);
    if (fail) throw StateError('synthetic unknown');
    return AssetImportReceipt.parse({
      'requestId': draft.requestId,
      'recordCount': draft.count,
      'recordIds': [createAssetImportRequestId()],
    }, draft);
  }
}

class RecoveryFiles implements InventoryRecoveryFiles {
  bool saved = true;
  Uint8List? selected;
  AssetImportRecovery? lastSaved;
  @override
  Future<String> digest(Uint8List bytes) async => 'a' * 64;
  @override
  Future<bool> save(AssetImportRecovery recovery) async {
    if (saved) lastSaved = recovery;
    return saved;
  }

  @override
  Future<Uint8List?> choose() async => selected;
}

Future<void> saveRecovery(WidgetTester tester) async {
  final save = find.text('Save private recovery JSON (Windows)');
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'file selection previews without writing; explicit confirmation writes once',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = Session();
      final source = Source();
      addTearDown(session.changes.close);
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryImportPage(
            apiBase: 'https://localhost/api/v1',
            recoveryFiles: RecoveryFiles(),
            session: session,
            source: source,
            files: Files(),
          ),
        ),
      );
      await tester.tap(find.text('Choose import JSON (Windows)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('New assets: 1'), findsOneWidget);
      expect(source.calls, 0);
      final confirm = find.widgetWithText(FilledButton, 'Confirm new records');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await saveRecovery(tester);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(source.calls, 1);
      expect(find.textContaining('Import confirmed.'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    },
  );

  testWidgets('session event invalidates confirmation without sending', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = Session();
    final source = Source();
    addTearDown(session.changes.close);
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryImportPage(
          apiBase: 'https://localhost/api/v1',
          recoveryFiles: RecoveryFiles(),
          session: session,
          source: source,
          files: Files(),
        ),
      ),
    );
    await tester.tap(find.text('Choose import JSON (Windows)'));
    await tester.pumpAndSettle();
    session.changes.add(2);
    await tester.pumpAndSettle();
    expect(find.textContaining('Session changed.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(source.calls, 0);
  });
  testWidgets('replacing a capability invalidates the old review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = Session();
    final files = Files();
    addTearDown(session.changes.close);
    Future<void> show(Source source) => tester.pumpWidget(
      MaterialApp(
        home: InventoryImportPage(
          apiBase: 'https://localhost/api/v1',
          recoveryFiles: RecoveryFiles(),
          session: session,
          source: source,
          files: files,
        ),
      ),
    );
    await show(Source());
    await tester.tap(find.text('Choose import JSON (Windows)'));
    await tester.pumpAndSettle();
    final replacement = Source();
    await show(replacement);
    await tester.pumpAndSettle();
    expect(find.textContaining('Import context changed.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Choose import JSON (Windows)'),
          )
          .onPressed,
      isNull,
    );
    expect(replacement.calls, 0);
  });
  testWidgets('late picker after context replacement cannot prepare a draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = Session();
    final source = Source();
    final files = Files()..selection = Completer<Uint8List?>();
    addTearDown(session.changes.close);
    Future<void> show(Source current) => tester.pumpWidget(
      MaterialApp(
        home: InventoryImportPage(
          apiBase: 'https://localhost/api/v1',
          recoveryFiles: RecoveryFiles(),
          session: session,
          source: current,
          files: files,
        ),
      ),
    );
    await show(source);
    await tester.tap(find.text('Choose import JSON (Windows)'));
    await tester.pump();
    final replacement = Source();
    await show(replacement);
    files.selection!.complete(files.bytes);
    await tester.pumpAndSettle();
    expect(find.textContaining('New assets:'), findsNothing);
    expect(files.hashes, 0);
    expect(source.calls + replacement.calls, 0);
    expect(find.textContaining('Import context changed.'), findsOneWidget);
  });
  testWidgets(
    'uncertain UI replay requires another acknowledgment and reuses exact draft',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = Session();
      final source = Source()..fail = true;
      addTearDown(session.changes.close);
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryImportPage(
            apiBase: 'https://localhost/api/v1',
            recoveryFiles: RecoveryFiles(),
            session: session,
            source: source,
            files: Files(),
          ),
        ),
      );
      await tester.tap(find.text('Choose import JSON (Windows)'));
      await tester.pumpAndSettle();
      Future<void> send(String label) async {
        await saveRecovery(tester);
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      await send('Confirm new records');
      expect(source.calls, 1);
      final retryButton = find.widgetWithText(
        FilledButton,
        'Replay same operation',
      );
      expect(tester.widget<FilledButton>(retryButton).onPressed, isNull);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(
                OutlinedButton,
                'Choose import JSON (Windows)',
              ),
            )
            .onPressed,
        isNull,
      );
      source.fail = false;
      await send('Replay same operation');
      expect(source.calls, 2);
      expect(identical(source.drafts[0], source.drafts[1]), isTrue);
      expect(find.textContaining('Import confirmed.'), findsOneWidget);
    },
  );
  for (final uncertain in [false, true]) {
    testWidgets('departure guard uncertain=$uncertain', (tester) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = Session();
      final source = Source()..fail = uncertain;
      addTearDown(session.changes.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => InventoryImportPage(
                    apiBase: 'https://localhost/api/v1',
                    recoveryFiles: RecoveryFiles(),
                    session: session,
                    source: source,
                    files: Files(),
                  ),
                ),
              ),
              child: const Text('Open import'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open import'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose import JSON (Windows)'));
      await tester.pumpAndSettle();
      if (uncertain) {
        await saveRecovery(tester);
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Confirm new records'));
        await tester.tap(find.text('Confirm new records'));
        await tester.pumpAndSettle();
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.text(uncertain ? 'Keep this operation' : 'Discard import draft?'),
        findsOneWidget,
      );
      expect(
        find.text('Discard draft'),
        uncertain ? findsNothing : findsOneWidget,
      );
      await tester.tap(find.text('Keep review'));
      await tester.pumpAndSettle();
      expect(find.textContaining('New assets: 1'), findsOneWidget);
      if (!uncertain) {
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Discard draft'));
        await tester.pumpAndSettle();
        expect(find.text('Open import'), findsOneWidget);
      } else {
        expect(source.calls, 1);
        expect(find.text('Replay same operation'), findsOneWidget);
      }
    });
  }
  for (final width in [390.0, 1440.0]) {
    testWidgets('import render $width at text 200%', (tester) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final font = Platform.environment['ASSET_DESK_UI_CAPTURE_FONT'];
      if (font != null) {
        final loader = FontLoader('Capture');
        loader.addFont(
          Future.value(ByteData.sublistView(File(font).readAsBytesSync())),
        );
        await loader.load();
      }
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = Session();
      addTearDown(session.changes.close);
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
            child: InventoryImportPage(
              apiBase: 'https://localhost/api/v1',
              recoveryFiles: RecoveryFiles(),
              session: session,
              source: Source(),
              files: Files(),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose import JSON (Windows)'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.textContaining('Checksum matches;'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Checksum matches;'), findsOneWidget);
      final directory = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
      if (directory != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$directory/import-${width.toInt()}-200.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}

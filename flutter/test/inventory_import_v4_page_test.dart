import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset_import.dart'
    show createAssetImportRequestId;
import 'package:asset_desk/api/asset_import_v4.dart';
import 'package:asset_desk/api/asset_session.dart';
import 'package:asset_desk/inventory_import_v4_page.dart';

import 'inventory_inspection_page_test.dart' as inspection;
import 'asset_export_v4_test.dart' show exportV4Fixture;

import 'package:asset_desk/inventory_v4_recovery_files.dart';
import 'package:asset_desk/api/asset_import_v4_recovery.dart';

class Files extends inspection.Files {
  Files() {
    bytes = Uint8List.fromList(utf8.encode(jsonEncode(exportV4Fixture())));
  }
}

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

class Source implements AssetImportV4Source {
  int calls = 0;
  bool fail = false;
  final drafts = <AssetImportV4Draft>[];
  @override
  Future<AssetImportV4Receipt> importInventoryV4(
    AssetImportV4Draft draft, {
    required int sessionRevision,
  }) async {
    calls++;
    drafts.add(draft);
    if (fail) throw StateError('synthetic unknown');
    return AssetImportV4Receipt.parse({
      'requestId': draft.requestId,
      'recordCount': draft.count,
      'recordIds': [createAssetImportRequestId()],
    }, draft);
  }
}

class RecoveryFiles implements InventoryV4RecoveryFiles {
  bool saved = true;
  Uint8List? selected;
  AssetImportV4Recovery? lastSaved;
  @override
  Future<String> digest(Uint8List bytes) async => 'a' * 64;
  @override
  Future<bool> save(AssetImportV4Recovery recovery) async {
    if (saved) lastSaved = recovery;
    return saved;
  }

  @override
  Future<Uint8List?> choose() async => selected;
}

Future<void> saveRecovery(WidgetTester tester) async {
  final save = find.text('Save private recovery JSON (Windows)');
  await tester.scrollUntilVisible(
    save,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  for (final invalid in [
    'malformed',
    'v2',
    'missing location',
    'missing check date',
  ]) {
    testWidgets('new invalid selection clears preview: $invalid', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = Session();
      addTearDown(session.changes.close);
      final files = Files();
      final source = Source();
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryImportV4Page(
            apiBase: 'https://localhost/api/v1',
            session: session,
            source: source,
            files: files,
            recoveryFiles: RecoveryFiles(),
          ),
        ),
      );
      final choose = find.text('Choose import JSON (Windows)');
      await tester.tap(choose);
      await tester.pumpAndSettle();
      expect(find.textContaining('Location: Room %_1'), findsOneWidget);
      expect(
        find.textContaining('Last checked date: 2024-03-01'),
        findsOneWidget,
      );
      final envelope = exportV4Fixture();
      if (invalid == 'v2') envelope['schemaVersion'] = 2;
      if (invalid == 'missing check date') {
        final payload =
            jsonDecode(envelope['payload'] as String) as Map<String, dynamic>;
        (payload['records'] as List).first.remove('lastCheckedDate');
        envelope['payload'] = jsonEncode(payload);
      }
      if (invalid == 'missing location') {
        final payload =
            jsonDecode(envelope['payload']! as String) as Map<String, dynamic>;
        (payload['records'] as List).first.remove('location');
        envelope['payload'] = jsonEncode(payload);
      }
      files.bytes = Uint8List.fromList(
        utf8.encode(invalid == 'malformed' ? '{' : jsonEncode(envelope)),
      );
      await tester.ensureVisible(choose);
      await tester.tap(choose);
      await tester.pumpAndSettle();
      expect(find.textContaining('Unable to prepare import.'), findsOneWidget);
      expect(find.textContaining('Checksum matches;'), findsNothing);
      expect(find.textContaining('Location: Room %_1'), findsNothing);
      expect(find.text('Confirm new records'), findsNothing);
      expect(source.calls, 0);
    });
  }
  testWidgets('v4 page rejects v1 export without fallback or submission', (
    tester,
  ) async {
    final session = Session();
    final source = Source();
    final files = Files()
      ..bytes = File('test/fixtures/inventory-export-v1.json')
          .readAsBytesSync();
    addTearDown(session.changes.close);
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryImportV4Page(
          apiBase: 'https://localhost/api/v1',
          session: session,
          source: source,
          files: files,
          recoveryFiles: RecoveryFiles(),
        ),
      ),
    );
    await tester.tap(find.text('Choose import JSON (Windows)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unable to prepare import.'), findsOneWidget);
    expect(find.textContaining('New assets:'), findsNothing);
    expect(source.calls, 0);
  });

  testWidgets('late digest failure preserves session invalidation message', (
    tester,
  ) async {
    final session = Session();
    final files = Files()..pending = Completer<String>();
    final source = Source();
    addTearDown(session.changes.close);
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryImportV4Page(
          apiBase: 'https://localhost/api/v1',
          session: session,
          source: source,
          files: files,
          recoveryFiles: RecoveryFiles(),
        ),
      ),
    );
    await tester.tap(find.text('Choose import JSON (Windows)'));
    await tester.pump();
    session.changes.add(2);
    await tester.pump();
    files.pending!.completeError(StateError('private digest error'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Session changed.'), findsOneWidget);
    expect(find.textContaining('Unable to prepare import.'), findsNothing);
    expect(source.calls, 0);
  });

  testWidgets(
    'restored v4 recovery never auto-sends and replays exact request',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = Session();
      final files = Files();
      final source = Source();
      final recovery = RecoveryFiles();
      addTearDown(session.changes.close);
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryImportV4Page(
            apiBase: 'https://localhost/api/v1',
            session: session,
            source: source,
            files: files,
            recoveryFiles: recovery,
          ),
        ),
      );
      await tester.tap(find.text('Choose import JSON (Windows)'));
      await tester.pumpAndSettle();
      await saveRecovery(tester);
      final saved = recovery.lastSaved!;
      // A different page instance models reopening after the original process ended.
      await tester.pumpWidget(const SizedBox());
      recovery.selected = Uint8List.fromList(utf8.encode(saved.json));
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryImportV4Page(
            apiBase: 'https://localhost/api/v1',
            session: session,
            source: source,
            files: files,
            recoveryFiles: recovery,
          ),
        ),
      );
      await tester.tap(find.text('Choose private recovery JSON (Windows)'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Recovery validated; outcome unknown.'),
        findsOneWidget,
      );
      expect(source.calls, 0);
      final replay = find.widgetWithText(FilledButton, 'Replay same operation');
      expect(tester.widget<FilledButton>(replay).onPressed, isNull);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(replay);
      await tester.tap(replay);
      await tester.pumpAndSettle();
      expect(source.calls, 1);
      expect(source.drafts.single.json, saved.draft.json);
      expect(source.drafts.single.requestId, saved.draft.requestId);
    },
  );

  testWidgets(
    'Cancel retains draft and cancelled recovery save cannot submit',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = Session();
      final source = Source();
      final files = Files();
      final recovery = RecoveryFiles()..saved = false;
      addTearDown(session.changes.close);
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryImportV4Page(
            apiBase: 'https://localhost/api/v1',
            session: session,
            source: source,
            files: files,
            recoveryFiles: recovery,
          ),
        ),
      );
      final choose = find.text('Choose import JSON (Windows)');
      await tester.tap(choose);
      await tester.pumpAndSettle();
      expect(find.textContaining('New assets: 1'), findsOneWidget);
      files.bytes = null;
      await tester.tap(choose);
      await tester.pumpAndSettle();
      expect(find.text('Selection cancelled. Draft retained.'), findsOneWidget);
      expect(find.textContaining('New assets: 1'), findsOneWidget);
      await saveRecovery(tester);
      expect(find.textContaining('Save cancelled.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm new records'),
            )
            .onPressed,
        isNull,
      );
      expect(source.calls, 0);
    },
  );

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
          home: InventoryImportV4Page(
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
        home: InventoryImportV4Page(
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
        home: InventoryImportV4Page(
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
        home: InventoryImportV4Page(
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
          home: InventoryImportV4Page(
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
                  builder: (_) => InventoryImportV4Page(
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
  for (final width in [390.0, 768.0, 1440.0]) {
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
            child: InventoryImportV4Page(
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
      await tester.pumpAndSettle();
      expect(find.textContaining('Checksum matches;'), findsOneWidget);
      final directory = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
      if (directory != null) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$directory/import-v4-${width.toInt()}-200.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.scrollUntilVisible(
          find.text('Confirm new records'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$directory/import-v4-${width.toInt()}-200-bottom.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}

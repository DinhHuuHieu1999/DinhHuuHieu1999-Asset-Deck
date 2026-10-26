import 'dart:async';
import 'dart:convert';

import 'package:asset_desk/api/asset_import_recovery.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/inventory_import_page.dart';

import 'inventory_import_page_test.dart' show Session, Source, RecoveryFiles;
import 'inventory_inspection_page_test.dart' show Files;

class DelayedRecoveryFiles extends RecoveryFiles {
  final pending = Completer<bool>();
  @override
  Future<bool> save(AssetImportRecovery recovery) => pending.future;
}

class DelayedRecoveryPicker extends RecoveryFiles {
  final pending = Completer<Uint8List?>();
  int digestCalls = 0;
  @override
  Future<Uint8List?> choose() => pending.future;
  @override
  Future<String> digest(Uint8List bytes) async {
    digestCalls++;
    return super.digest(bytes);
  }
}

class DelayedRecoveryDigest extends RecoveryFiles {
  final pending = Completer<String>();
  @override
  Future<String> digest(Uint8List bytes) => pending.future;
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    Session session,
    Source source,
    RecoveryFiles recovery,
  ) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryImportPage(
          session: session,
          source: source,
          files: Files(),
          apiBase: 'https://localhost/api/v1',
          recoveryFiles: recovery,
        ),
      ),
    );
  }

  Future<void> click(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'save cancel blocks submission; saved file still needs fresh acknowledgement',
    (tester) async {
      final session = Session();
      final source = Source();
      final recovery = RecoveryFiles()..saved = false;
      addTearDown(session.changes.close);
      await mount(tester, session, source, recovery);
      await click(tester, 'Choose import JSON (Windows)');
      final confirm = find.widgetWithText(FilledButton, 'Confirm new records');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await click(tester, 'Save private recovery JSON (Windows)');
      expect(find.textContaining('Save cancelled.'), findsOneWidget);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      expect(source.calls, 0);
      recovery.saved = true;
      await click(tester, 'Save private recovery JSON (Windows)');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await click(tester, 'Confirm new records');
      expect(source.calls, 1);
      expect(source.drafts.single.json, recovery.lastSaved!.draft.json);
    },
  );
  testWidgets(
    'reconstruction loads exact saved operation with no write then explicit same-key replay',
    (tester) async {
      final session = Session();
      final source = Source();
      final recovery = RecoveryFiles();
      addTearDown(session.changes.close);
      await mount(tester, session, source, recovery);
      await click(tester, 'Choose import JSON (Windows)');
      await click(tester, 'Save private recovery JSON (Windows)');
      final saved = recovery.lastSaved!;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      recovery.selected = Uint8List.fromList(utf8.encode(saved.json));
      await mount(tester, session, source, recovery);
      await click(tester, 'Choose private recovery JSON (Windows)');
      expect(source.calls, 0);
      expect(find.textContaining('outcome unknown'), findsOneWidget);
      final replay = find.widgetWithText(FilledButton, 'Replay same operation');
      expect(tester.widget<FilledButton>(replay).onPressed, isNull);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await click(tester, 'Replay same operation');
      expect(source.calls, 1);
      expect(source.drafts.single.json, saved.draft.json);
      expect(source.drafts.single.requestId, saved.draft.requestId);
    },
  );
  testWidgets(
    'recovery picker Cancel preserves existing preview without writing',
    (tester) async {
      final session = Session();
      final source = Source();
      final recovery = RecoveryFiles();
      addTearDown(session.changes.close);
      await mount(tester, session, source, recovery);
      await click(tester, 'Choose import JSON (Windows)');
      await click(tester, 'Choose private recovery JSON (Windows)');
      expect(find.textContaining('New assets: 1'), findsOneWidget);
      expect(
        find.textContaining('Recovery selection cancelled'),
        findsOneWidget,
      );
      expect(source.calls, 0);
    },
  );
  for (final fail in [false, true]) {
    testWidgets('late save completion is fail-closed, failure=$fail', (
      tester,
    ) async {
      final session = Session();
      final source = Source();
      final recovery = DelayedRecoveryFiles();
      addTearDown(session.changes.close);
      await mount(tester, session, source, recovery);
      await click(tester, 'Choose import JSON (Windows)');
      await tester.ensureVisible(
        find.text('Save private recovery JSON (Windows)'),
      );
      await tester.tap(find.text('Save private recovery JSON (Windows)'));
      await tester.pump();
      if (fail) {
        recovery.pending.completeError(StateError('private synthetic failure'));
      } else {
        session.changes.add(2);
        await tester.pump();
        recovery.pending.complete(true);
      }
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          fail ? 'Unable to save recovery.' : 'Session changed.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm new records'),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('private synthetic failure'), findsNothing);
      expect(source.calls, 0);
    });
  }
  testWidgets('malformed recovery clears unsent preview without writing', (
    tester,
  ) async {
    final session = Session();
    final source = Source();
    final recovery = RecoveryFiles()
      ..selected = Uint8List.fromList(utf8.encode('{}'));
    addTearDown(session.changes.close);
    await mount(tester, session, source, recovery);
    await click(tester, 'Choose import JSON (Windows)');
    await click(tester, 'Choose private recovery JSON (Windows)');
    expect(find.textContaining('Unable to restore recovery.'), findsOneWidget);
    expect(find.textContaining('New assets:'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(source.calls, 0);
  });
  for (final dispose in [false, true]) {
    testWidgets(
      'late recovery picker is ignored after context loss, dispose=$dispose',
      (tester) async {
        final session = Session();
        final source = Source();
        final recovery = DelayedRecoveryPicker();
        addTearDown(session.changes.close);
        await mount(tester, session, source, recovery);
        await tester.tap(find.text('Choose private recovery JSON (Windows)'));
        await tester.pump();
        if (dispose) {
          await tester.pumpWidget(const SizedBox());
        } else {
          session.changes.add(2);
          await tester.pump();
        }
        recovery.pending.complete(Uint8List.fromList(utf8.encode('{}')));
        await tester.pumpAndSettle();
        expect(recovery.digestCalls, 0);
        expect(source.calls, 0);
        expect(find.textContaining('Recovery validated'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'recovery from another configured endpoint is rejected before replay',
    (tester) async {
      final session = Session();
      final source = Source();
      final recovery = RecoveryFiles();
      addTearDown(session.changes.close);
      await mount(tester, session, source, recovery);
      await click(tester, 'Choose import JSON (Windows)');
      await click(tester, 'Save private recovery JSON (Windows)');
      final saved = recovery.lastSaved!;
      recovery.selected = Uint8List.fromList(
        utf8.encode(saved.json.replaceAll('localhost', 'other.invalid')),
      );
      await click(tester, 'Choose private recovery JSON (Windows)');
      expect(
        find.textContaining('Unable to restore recovery.'),
        findsOneWidget,
      );
      expect(find.textContaining('New assets:'), findsNothing);
      expect(source.calls, 0);
    },
  );
  testWidgets(
    'late checksum cannot restore actionable review after session change',
    (tester) async {
      final session = Session();
      final source = Source();
      final originalFiles = RecoveryFiles();
      addTearDown(session.changes.close);
      await mount(tester, session, source, originalFiles);
      await click(tester, 'Choose import JSON (Windows)');
      await click(tester, 'Save private recovery JSON (Windows)');
      final saved = originalFiles.lastSaved!;
      await tester.pumpWidget(const SizedBox());
      final delayed = DelayedRecoveryDigest()
        ..selected = Uint8List.fromList(utf8.encode(saved.json));
      await mount(tester, session, source, delayed);
      await tester.tap(find.text('Choose private recovery JSON (Windows)'));
      await tester.pump();
      session.changes.add(2);
      await tester.pump();
      delayed.pending.complete('a' * 64);
      await tester.pumpAndSettle();
      expect(find.textContaining('Session changed.'), findsOneWidget);
      expect(find.textContaining('Recovery validated'), findsNothing);
      expect(find.text('Replay same operation'), findsNothing);
      expect(source.calls, 0);
    },
  );
}

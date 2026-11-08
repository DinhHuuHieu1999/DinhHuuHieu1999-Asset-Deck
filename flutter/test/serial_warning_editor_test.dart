import 'dart:io';
import 'dart:async';

import 'package:asset_desk/api/asset_serial_check.dart';
import 'package:asset_desk/api/asset.dart';

import 'asset_test.dart' show record;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/asset_editor.dart';

import 'assets_page_test.dart' show FakeStore;

class SerialStore extends FakeStore implements AssetSerialCheckSource {
  final checks = <String>[];
  bool duplicate = true, fail = false;
  Completer<bool>? pending;
  @override
  Future<bool> serialDuplicate(String serial, {String? excludeId}) async {
    checks.add('$serial|$excludeId');
    if (fail) throw StateError('synthetic failure');
    return pending == null ? duplicate : pending!.future;
  }
}

Future<void> openEditor(
  WidgetTester tester,
  FakeStore store, {
  AssetRecord? original,
}) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: AssetEditor(store: store, original: original),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> check(WidgetTester tester) async {
  await tester.pump();
  await tester.ensureVisible(find.text('Check duplicate serial'));
  await tester.tap(find.text('Check duplicate serial'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'duplicate warning is explicit, literal, invalidated on serial edit and does not block save',
    (tester) async {
      final store = SerialStore();
      await openEditor(tester, store);
      await tester.enterText(find.byType(TextField).at(0), 'Test');
      await tester.enterText(find.byType(TextField).at(1), 'fixture');
      await tester.enterText(find.byType(TextField).at(2), ' %_1 ');
      expect(store.checks, isEmpty);
      await check(tester);
      expect(store.checks, ['%_1|null']);
      expect(
        find.text(
          'Duplicate serial found in your inventory. Saving is still allowed.',
        ),
        findsOneWidget,
      );
      expect(store.writes, 0);
      await tester.ensureVisible(find.text('Save asset'));
      await tester.tap(find.text('Save asset'));
      await tester.pumpAndSettle();
      expect(store.writes, 1);
    },
  );
  testWidgets(
    'edit excludes its own ID and changing serial clears previous result',
    (tester) async {
      final store = SerialStore()..duplicate = false;
      final original = AssetRecord.fromJson(record());
      await openEditor(tester, store, original: original);
      await tester.enterText(find.byType(TextField).at(2), 'AbC');
      await check(tester);
      expect(store.checks.last, 'AbC|${original.id}');
      expect(find.textContaining('No other asset currently'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(2), 'abc');
      await tester.pumpAndSettle();
      expect(find.textContaining('No other asset currently'), findsNothing);
      expect(store.writes, 0);
    },
  );
  testWidgets('failed check is not clear and preserves all draft fields', (
    tester,
  ) async {
    final store = SerialStore()..fail = true;
    await openEditor(tester, store);
    await tester.enterText(find.byType(TextField).at(0), 'Draft');
    await tester.enterText(find.byType(TextField).at(2), 'X');
    await check(tester);
    expect(find.textContaining('Serial check unavailable.'), findsOneWidget);
    expect(find.textContaining('No other asset currently'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Draft',
    );
    expect(store.writes, 0);
  });
  testWidgets(
    'late response after serial change cannot restore stale warning',
    (tester) async {
      final store = SerialStore()..pending = Completer<bool>();
      await openEditor(tester, store);
      await tester.enterText(find.byType(TextField).at(2), 'old');
      await tester.tap(find.text('Check duplicate serial'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(2), 'new');
      store.pending!.complete(true);
      await tester.pumpAndSettle();
      expect(find.textContaining('Duplicate serial found'), findsNothing);
      expect(store.writes, 0);
    },
  );
  testWidgets(
    'blank serial disables check and unavailable capability keeps old editor',
    (tester) async {
      await openEditor(tester, SerialStore());
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Check duplicate serial'),
      );
      expect(button.onPressed, isNull);
      await tester.pumpWidget(
        MaterialApp(home: AssetEditor(store: FakeStore())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Check duplicate serial'), findsNothing);
    },
  );
  testWidgets('late response after disposal is ignored', (tester) async {
    final store = SerialStore()..pending = Completer<bool>();
    await openEditor(tester, store);
    await tester.enterText(find.byType(TextField).at(2), 'old');
    await tester.pump();
    await tester.tap(find.text('Check duplicate serial'));
    await tester.pump();
    expect(store.checks, hasLength(1));
    await tester.pumpWidget(const MaterialApp(home: Text('Signed out')));
    store.pending!.complete(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Duplicate serial found'), findsNothing);
  });
  for (final brightness in Brightness.values) {
    testWidgets('duplicate uses readable amber warning in $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: AssetEditor(store: SerialStore()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(2), '%_1');
      await check(tester);
      final text = find.textContaining('Duplicate serial found');
      final container = tester.widget<Container>(
        find.ancestor(of: text, matching: find.byType(Container)).first,
      );
      final bg = (container.decoration! as BoxDecoration).color!;
      final fg = tester.widget<Text>(text).style!.color!;
      final warning = ColorScheme.fromSeed(
        seedColor: Colors.amber,
        brightness: brightness,
      );
      expect(bg, warning.primaryContainer);
      expect(fg, warning.onPrimaryContainer);
      final a = bg.computeLuminance(), b = fg.computeLuminance();
      final contrast = a > b
          ? (a + 0.05) / (b + 0.05)
          : (b + 0.05) / (a + 0.05);
      expect(contrast, greaterThanOrEqualTo(4.5));
    });
  }
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('editor render $width at 200%', (tester) async {
      final font = Platform.environment['ASSET_DESK_UI_CAPTURE_FONT'];
      if (font != null) {
        final loader = FontLoader('Capture');
        loader.addFont(
          Future.value(ByteData.sublistView(File(font).readAsBytesSync())),
        );
        await loader.load();
      }
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
            child: AssetEditor(store: SerialStore()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(2), '%_1');
      await check(tester);
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
      if (directory != null)
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$directory/editor-${width.toInt()}-200.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
    });
  }
}

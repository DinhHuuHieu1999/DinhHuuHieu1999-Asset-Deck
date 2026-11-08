import 'dart:async';

import 'asset_desk_app_test.dart' show FakeSession;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset.dart';
import 'package:asset_desk/asset_details_page.dart';

import 'asset_test.dart' show record;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('copies exact displayed serial only on explicit action', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AssetDetailsPage(
          record: AssetRecord.fromJson({...record(), 'serial': 'NATIVE-%_1'}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'Clipboard.setData'), isEmpty);
    await tester.ensureVisible(find.text('Copy serial'));
    await tester.tap(find.text('Copy serial'));
    await tester.pumpAndSettle();
    final copy = calls.singleWhere((c) => c.method == 'Clipboard.setData');
    expect(copy.arguments, {'text': 'NATIVE-%_1'});
    expect(find.text('Serial copied'), findsOneWidget);
  });
  testWidgets('empty serial disables copy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AssetDetailsPage(record: AssetRecord.fromJson(record())),
      ),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Copy serial'),
    );
    expect(button.onPressed, isNull);
  });
  testWidgets('clipboard failure is visible without private value', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData')
          throw PlatformException(code: 'synthetic');
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AssetDetailsPage(
          record: AssetRecord.fromJson({
            ...record(),
            'serial': 'private-serial',
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Copy serial'));
    await tester.tap(find.text('Copy serial'));
    await tester.pumpAndSettle();
    expect(find.text('Could not copy serial. Try again.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'pending copy blocks duplicates and sign-out suppresses late feedback',
    (tester) async {
      final pending = Completer<void>();
      final session = FakeSession();
      addTearDown(session.events.close);
      var writes = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            writes++;
            await pending.future;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AssetDetailsPage(
            session: session,
            record: AssetRecord.fromJson({
              ...record(),
              'serial': 'private-serial',
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Copy serial'));
      await tester.tap(find.text('Copy serial'));
      await tester.pump();
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Copy serial'),
      );
      expect(button.onPressed, isNull);
      expect(writes, 1);
      session.signOut();
      await tester.pumpAndSettle();
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Serial copied'), findsNothing);
      expect(find.text('Copy serial'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

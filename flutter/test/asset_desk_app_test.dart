import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:asset_desk/api/asset.dart';
import 'package:asset_desk/api/asset_session.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:asset_desk/asset_desk_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'asset_test.dart' show record;

class FakeSession implements AssetSession {
  final events = StreamController<int>.broadcast();
  @override
  AssetAccount? account;
  @override
  int sessionRevision = 0;
  @override
  Stream<int> get sessionChanges => events.stream;
  String? password;
  String? identifier;
  AssetFailure? authFailure;
  bool closed = false, expire = false;
  Completer<AssetPage>? delayedPage;
  final writes = <AssetInput>[];
  @override
  Future<void> login(String identifier, String password) async {
    this.identifier = identifier;
    this.password = password;
    if (authFailure != null) throw authFailure!;
    account = const AssetAccount(
      id: 'aaaaaaaaaaaaaaaaaaaaaaaa',
      name: 'Synthetic owner',
    );
    events.add(++sessionRevision);
  }

  @override
  Future<void> register({
    required String email,
    required String username,
    required String name,
    required String password,
  }) => login(username, password);
  @override
  void signOut() {
    account = null;
    events.add(++sessionRevision);
  }

  @override
  void close() {
    closed = true;
    unawaited(events.close());
  }

  @override
  Future<AssetPage> list({
    required String query,
    required String status,
    String category = '',
    required int offset,
  }) async {
    if (expire) {
      signOut();
      throw const AssetFailure('Please sign in again', statusCode: 401);
    }
    if (delayedPage != null) return delayedPage!.future;
    return AssetPage([AssetRecord.fromJson(record())], null);
  }

  @override
  Future<AssetRecord> create(AssetInput input) async {
    writes.add(input);
    return AssetRecord.fromJson(record());
  }

  @override
  Future<AssetRecord> update(AssetRecord original, AssetInput input) =>
      create(input);
}

Future<void> open(WidgetTester tester, FakeSession session) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(AssetDeskApp(session: session));
  await tester.pumpAndSettle();
}

Future<void> login(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), 'synthetic');
  await tester.enterText(find.byType(TextField).at(1), 'synthetic-pass');
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'login shows private inventory; sign out clears it and password',
    (tester) async {
      final session = FakeSession();
      await open(tester, session);
      expect(find.text('Laptop'), findsNothing);
      await login(tester);
      expect(find.text('Laptop'), findsOneWidget);
      expect(find.text('Signed in: Synthetic owner'), findsOneWidget);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Laptop'), findsNothing);
      expect(find.text('Signed in: Synthetic owner'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        isEmpty,
      );
      expect(find.text('synthetic-pass'), findsNothing);
    },
  );
  testWidgets('sign out destroys nested editor and its draft', (tester) async {
    final session = FakeSession();
    await open(tester, session);
    await login(tester);
    await tester.tap(find.text('Add asset'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Private draft');
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Private draft'), findsNothing);
    expect(find.text('Add asset'), findsNothing);
    await login(tester);
    await tester.tap(find.text('Add asset'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      isEmpty,
    );
    expect(session.writes, isEmpty);
  });
  testWidgets(
    '401 refresh destroys private views instead of keeping stale account data',
    (tester) async {
      final session = FakeSession();
      await open(tester, session);
      await login(tester);
      session.expire = true;
      await tester.tap(find.text('Refresh inventory'));
      await tester.pumpAndSettle();
      expect(find.text('Laptop'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    },
  );
  testWidgets('late list cannot reappear after sign-out', (tester) async {
    final session = FakeSession();
    await open(tester, session);
    await login(tester);
    session.delayedPage = Completer<AssetPage>();
    await tester.tap(find.text('Refresh inventory'));
    await tester.pump();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    session.delayedPage!.complete(
      AssetPage([AssetRecord.fromJson(record())], null),
    );
    await tester.pumpAndSettle();
    expect(find.text('Laptop'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed login clears password and retains safe error', (
    tester,
  ) async {
    final session = FakeSession()
      ..authFailure = const AssetFailure(
        'Please sign in again',
        statusCode: 401,
      );
    await open(tester, session);
    await login(tester);
    expect(find.text('Please sign in again'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      isEmpty,
    );
  });
  testWidgets(
    'unknown registration outcome blocks resubmit and offers existing account',
    (tester) async {
      final session = FakeSession()
        ..authFailure = const AssetFailure('Request timed out');
      await open(tester, session);
      await tester.tap(find.text('Create a new account'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await tester.enterText(find.byType(TextField).at(i), 'synthetic');
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Registration may have completed'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create account'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Use existing account'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    },
  );
  testWidgets(
    'replacing session closes previous account and private navigator',
    (tester) async {
      final first = FakeSession(), second = FakeSession();
      await open(tester, first);
      await login(tester);
      await tester.pumpWidget(AssetDeskApp(session: second));
      await tester.pumpAndSettle();
      expect(first.closed, isTrue);
      expect(find.text('Laptop'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(second.closed, isTrue);
    },
  );
  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('auth and account inventory render $width at text 200%', (
      tester,
    ) async {
      final font = Platform.environment['ASSET_DESK_UI_CAPTURE_FONT'];
      if (font != null) {
        final loader = FontLoader('Roboto');
        loader.addFont(
          Future.value(ByteData.sublistView(File(font).readAsBytesSync())),
        );
        await loader.load();
      }
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = FakeSession();
      final icons = Platform.environment['ASSET_DESK_UI_CAPTURE_ICONS'];
      if (icons != null) {
        final loader = FontLoader('MaterialIcons');
        loader.addFont(
          Future.value(ByteData.sublistView(File(icons).readAsBytesSync())),
        );
        await loader.load();
      }
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final semantics = tester.ensureSemantics();
      try {
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: AssetDeskApp(session: session),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> capture(String state) async {
          expect(tester.takeException(), isNull);
          final directory = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
          if (directory == null) return;
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('$directory/$state-${width.toInt()}-200.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        expect(
          MediaQuery.textScalerOf(
            tester.element(find.text('Sign in to your inventory')),
          ).scale(10),
          20,
        );
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await capture('sign-in');
        await session.login('synthetic', 'synthetic-pass');
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await capture('signed-in');
      } finally {
        semantics.dispose();
      }
    });
  }
}

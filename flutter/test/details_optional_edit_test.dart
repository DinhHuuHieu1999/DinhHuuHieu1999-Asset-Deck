import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset.dart';
import 'package:asset_desk/api/asset_dates.dart';
import 'package:asset_desk/api/asset_location.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:asset_desk/asset_details_page.dart';
import 'package:asset_desk/asset_desk_app.dart';
import 'package:asset_desk/assets_page.dart';

import 'asset_test.dart' show record;
import 'assets_page_test.dart' show FakeStore;
import 'asset_desk_app_test.dart' show FakeSession;

const datesAction = 'Edit purchase / warranty dates';

class OptionalStore extends FakeStore
    implements AssetDatesSource, AssetLocationSource {
  int version = 9,
      dateReads = 0,
      locationReads = 0,
      dateWrites = 0,
      locationWrites = 0;
  AssetDatesInput dates = const AssetDatesInput(
    purchasedOn: '2024-02-29',
    warrantyExpiresOn: '2027-02-28',
  );
  String? location = 'Synthetic room %_1';
  AssetDates? readDateValue, writtenDateOriginal;
  AssetLocation? readLocationValue, writtenLocationOriginal;
  AssetFailure? writeFailure;
  Future<AssetDates>? pendingDates;
  bool wrongDateVersion = false;
  AssetRecord get selected =>
      AssetRecord.fromJson({...record(3), 'version': version});
  @override
  Future<AssetPage> list({
    String sort = 'updated_desc',
    required String query,
    required String status,
    String category = '',
    required int offset,
  }) {
    pages = {
      offset: AssetPage([selected], null),
    };
    return super.list(
      sort: sort,
      query: query,
      status: status,
      category: category,
      offset: offset,
    );
  }

  @override
  Future<AssetLocationPage> listLocations({
    String sort = 'updated_desc',
    required String query,
    required String status,
    String category = '',
    required int offset,
    String locationMode = 'all',
    String? location,
    String warranty = '',
    String asOf = '',
  }) async {
    final page = await list(
      sort: sort,
      query: query,
      status: status,
      category: category,
      offset: offset,
    );
    return AssetLocationPage(
      page.items.map((a) => AssetLocationEntry(a, this.location)).toList(),
      page.nextOffset,
    );
  }

  @override
  Future<AssetDates> readDates(String id) async {
    dateReads++;
    if (pendingDates != null) return pendingDates!;
    return readDateValue = AssetDates(
      id: id,
      version: wrongDateVersion ? version + 1 : version,
      input: dates,
    );
  }

  @override
  Future<AssetLocation> readLocation(String id) async {
    locationReads++;
    return readLocationValue = AssetLocation(
      id: id,
      version: version,
      location: location,
    );
  }

  @override
  Future<AssetDates> updateDates(
    AssetDates original,
    AssetDatesInput input,
  ) async {
    dateWrites++;
    writtenDateOriginal = original;
    if (writeFailure != null) throw writeFailure!;
    dates = input;
    return AssetDates(id: original.id, version: ++version, input: input);
  }

  @override
  Future<AssetLocation> updateLocation(
    AssetLocation original,
    String? value,
  ) async {
    locationWrites++;
    writtenLocationOriginal = original;
    if (writeFailure != null) throw writeFailure!;
    location = value;
    return AssetLocation(id: original.id, version: ++version, location: value);
  }

  @override
  Future<AssetRecord> update(AssetRecord original, AssetInput input) =>
      throw StateError('Base fields must not be written');
}

class OptionalSession extends FakeSession
    implements AssetDatesSource, AssetLocationSource {
  final data = OptionalStore();
  final datePending = Completer<AssetDates>();
  final locationPending = Completer<AssetLocation>();
  @override
  Future<AssetPage> list({
    String sort = 'updated_desc',
    required String query,
    required String status,
    String category = '',
    required int offset,
  }) => data.list(
    sort: sort,
    query: query,
    status: status,
    category: category,
    offset: offset,
  );
  @override
  Future<AssetDates> readDates(String id) => data.readDates(id);
  @override
  Future<AssetLocation> readLocation(String id) => data.readLocation(id);
  @override
  Future<AssetDates> updateDates(AssetDates original, AssetDatesInput input) {
    data.dateWrites++;
    return datePending.future;
  }

  @override
  Future<AssetLocation> updateLocation(
    AssetLocation original,
    String? location,
  ) {
    data.locationWrites++;
    return locationPending.future;
  }

  @override
  Future<AssetLocationPage> listLocations({
    String sort = 'updated_desc',
    required String query,
    required String status,
    String category = '',
    required int offset,
    String locationMode = 'all',
    String? location,
    String warranty = '',
    String asOf = '',
  }) => data.listLocations(
    sort: sort,
    query: query,
    status: status,
    category: category,
    offset: offset,
    locationMode: locationMode,
    location: location,
    warranty: warranty,
    asOf: asOf,
  );
}

Future<void> openInventory(
  WidgetTester tester,
  FakeStore store, {
  bool dates = true,
  bool location = true,
}) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: AssetsPage(
        store: store,
        enableAssetDates: dates,
        enableAssetLocation: location,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openDetails(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('View details'),
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('View details'));
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label),
    200,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  for (final kind in ['dates', 'location']) {
    final action = kind == 'dates' ? datesAction : 'Edit location';
    final save = kind == 'dates' ? 'Save dates' : 'Save location';
    final draft = kind == 'dates' ? '2024-03-01' : 'Changed room %_2';
    testWidgets(
      '$kind Save uses verified original without reread and preserves other fields',
      (tester) async {
        final store = OptionalStore();
        await openInventory(tester, store);
        await tester.enterText(find.byType(TextField).first, 'applied');
        await tapVisible(tester, 'Apply filters');
        await tester.enterText(find.byType(TextField).first, 'unsent');
        await openDetails(tester);
        final originalDates = store.readDateValue;
        final originalLocation = store.readLocationValue;
        await tapVisible(tester, action);
        await tester.enterText(find.byType(TextField).first, draft);
        await tapVisible(tester, save);
        expect(find.text('Asset details'), findsNothing);
        expect(store.calls.last, 'applied||0');
        expect(find.text('unsent'), findsOneWidget);
        expect(store.dateReads, 1);
        expect(store.locationReads, 1);
        expect(store.writes, 0);
        expect(
          store.selected.input.toJson(),
          AssetRecord.fromJson(record(3)).input.toJson(),
        );
        if (kind == 'dates') {
          expect(identical(store.writtenDateOriginal, originalDates), isTrue);
          expect(store.writtenDateOriginal!.version, 9);
          expect(store.dates.purchasedOn, draft);
          expect(store.dates.warrantyExpiresOn, '2027-02-28');
          expect(store.location, 'Synthetic room %_1');
          expect(store.locationWrites, 0);
        } else {
          expect(
            identical(store.writtenLocationOriginal, originalLocation),
            isTrue,
          );
          expect(store.writtenLocationOriginal!.version, 9);
          expect(store.location, draft);
          expect(store.dates.purchasedOn, '2024-02-29');
          expect(store.dates.warrantyExpiresOn, '2027-02-28');
          expect(store.dateWrites, 0);
        }
      },
    );
    testWidgets(
      '$kind Keep/Discard returns to unchanged snapshot without reload',
      (tester) async {
        final store = OptionalStore();
        await openInventory(tester, store);
        await openDetails(tester);
        await tapVisible(tester, action);
        await tester.enterText(find.byType(TextField).first, draft);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tapVisible(tester, 'Keep editing');
        expect(find.text(draft), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tapVisible(tester, 'Discard');
        expect(find.text('Asset details'), findsOneWidget);
        expect(store.calls.length, 1);
        expect(store.dateWrites + store.locationWrites, 0);
        expect(store.dateReads, 1);
        expect(store.locationReads, 1);
      },
    );
    for (final status in [409, 503]) {
      testWidgets('$kind $status preserves draft and blocks resubmission', (
        tester,
      ) async {
        final store = OptionalStore()
          ..writeFailure = AssetFailure(
            'Synthetic failure',
            statusCode: status,
          );
        await openInventory(tester, store);
        await openDetails(tester);
        await tapVisible(tester, action);
        await tester.enterText(find.byType(TextField).first, draft);
        await tapVisible(tester, save);
        expect(find.text(draft), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, save))
              .onPressed,
          isNull,
        );
        expect(store.dateWrites + store.locationWrites, 1);
        expect(store.calls.length, 1);
      });
    }
  }

  testWidgets('Flags and source capabilities gate optional edit actions', (
    tester,
  ) async {
    await openInventory(tester, OptionalStore(), dates: false, location: false);
    await openDetails(tester);
    expect(find.text(datesAction), findsNothing);
    expect(find.text('Edit location'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await openInventory(tester, FakeStore());
    await openDetails(tester);
    expect(find.text(datesAction), findsNothing);
    expect(find.text('Edit location'), findsNothing);
  });

  testWidgets('Mismatched shared version disables every edit', (tester) async {
    final store = OptionalStore()..wrongDateVersion = true;
    await openInventory(tester, store);
    await openDetails(tester);
    for (final label in ['Edit asset', datesAction, 'Edit location']) {
      await tester.scrollUntilVisible(
        find.text(label),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label))
            .onPressed,
        isNull,
      );
    }
    expect(store.locationReads, 0);
    expect(store.dateWrites + store.locationWrites, 0);
  });

  testWidgets('Explicit Unknown values remain editable', (tester) async {
    final store = OptionalStore()
      ..dates = const AssetDatesInput(
        purchasedOn: null,
        warrantyExpiresOn: null,
      )
      ..location = null;
    await openInventory(tester, store);
    await openDetails(tester);
    await tapVisible(tester, datesAction);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      isEmpty,
    );
    await tester.enterText(find.byType(TextField).first, '2024-02-29');
    await tapVisible(tester, 'Save dates');
    expect(store.dates.purchasedOn, '2024-02-29');
    await openDetails(tester);
    await tapVisible(tester, 'Edit location');
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      isEmpty,
    );
  });

  testWidgets('Session invalidation ignores late optional edit success', (
    tester,
  ) async {
    final store = OptionalStore();
    final session = FakeSession();
    addTearDown(session.close);
    final pending = Completer<bool>();
    await tester.pumpWidget(
      MaterialApp(
        home: AssetDetailsPage(
          record: store.selected,
          datesSource: store,
          locationSource: store,
          session: session,
          onEditDates: (_) => pending.future,
          onEditLocation: (_) async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(datesAction));
    await tester.tap(find.text(datesAction));
    await tester.pump();
    await tester.ensureVisible(find.text('Edit location'));
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Edit location'),
          )
          .onPressed,
      isNull,
    );
    session.signOut();
    await tester.pump();
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(find.textContaining('Session changed'), findsOneWidget);
    expect(find.text('Laptop'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pending and failed optional reads do not enable edits', (
    tester,
  ) async {
    final pending = Completer<AssetDates>();
    final store = OptionalStore()..pendingDates = pending.future;
    await tester.pumpWidget(
      MaterialApp(
        home: AssetDetailsPage(
          record: store.selected,
          datesSource: store,
          locationSource: store,
          onEditDates: (_) async => false,
          onEditLocation: (_) async => false,
        ),
      ),
    );
    await tester.pump();
    for (final label in [datesAction, 'Edit location']) {
      await tester.scrollUntilVisible(
        find.text(label),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label))
            .onPressed,
        isNull,
      );
    }
    pending.completeError(StateError('Synthetic read failure'));
    await tester.pumpAndSettle();
    for (final label in [datesAction, 'Edit location']) {
      await tester.scrollUntilVisible(
        find.text(label),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label))
            .onPressed,
        isNull,
      );
    }
    expect(store.locationReads, 0);
    expect(store.dateWrites + store.locationWrites, 0);
  });

  for (final kind in ['dates', 'location']) {
    testWidgets('Root sign-out clears pending $kind editor and late results', (
      tester,
    ) async {
      final session = OptionalSession();
      await session.login('synthetic', 'not-a-real-credential');
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        AssetDeskApp(
          session: session,
          enableAssetDates: true,
          enableAssetLocation: true,
        ),
      );
      await tester.pumpAndSettle();
      await openDetails(tester);
      await tapVisible(tester, kind == 'dates' ? datesAction : 'Edit location');
      await tester.enterText(
        find.byType(TextField).first,
        kind == 'dates' ? '2024-03-01' : 'Private room draft',
      );
      await tester.ensureVisible(
        find.text(kind == 'dates' ? 'Save dates' : 'Save location'),
      );
      await tester.tap(
        find.text(kind == 'dates' ? 'Save dates' : 'Save location'),
      );
      await tester.pump();
      expect(session.data.dateWrites + session.data.locationWrites, 1);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      if (kind == 'dates') {
        session.datePending.complete(
          AssetDates(
            id: session.data.selected.id,
            version: 10,
            input: session.data.dates,
          ),
        );
      } else {
        session.locationPending.complete(
          AssetLocation(
            id: session.data.selected.id,
            version: 10,
            location: 'Private room draft',
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('Asset details'), findsNothing);
      expect(find.text('Private room draft'), findsNothing);
      expect(find.text('Laptop'), findsNothing);
      expect(find.text('Sign in'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('Optional edit actions render at $width and text 200%', (
      tester,
    ) async {
      final font = Platform.environment['ASSET_DESK_UI_CAPTURE_FONT'];
      if (font != null) {
        final loader = FontLoader('Capture');
        loader.addFont(
          Future.value(ByteData.sublistView(File(font).readAsBytesSync())),
        );
        await loader.load();
      }
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = OptionalStore();
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
            child: AssetDetailsPage(
              record: store.selected,
              datesSource: store,
              locationSource: store,
              onEdit: (_) async => false,
              onEditDates: (_) async => false,
              onEditLocation: (_) async => false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in [datesAction, 'Edit location']) {
        await tester.scrollUntilVisible(
          find.text(label),
          200,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, label),
              )
              .onPressed,
          isNotNull,
        );
        final directory = Platform.environment['ASSET_DESK_UI_CAPTURE_DIR'];
        if (directory != null) {
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final section = label == datesAction ? 'dates' : 'location';
            final file = File('$directory/$section-${width.toInt()}-200.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
    });
  }
}

import 'package:flutter/material.dart';
import 'package:asset_desk/asset_details_page.dart';

import 'dart:async';

import 'package:asset_desk/api/asset.dart';
import 'package:asset_desk/api/asset_details.dart';

import 'asset_test.dart' show record;

import 'package:asset_desk/api/asset_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  Map<String, Object?> row() => {
    'id': id,
    'version': 1,
    'lastCheckedOn': '2024-02-29',
  };
  test(
    'details accepts only check dates matching the selected version',
    () async {
      final asset = AssetRecord.fromJson(record());
      final source = CheckSource();
      final snapshot = await AssetDetailsSnapshot.load(
        asset,
        checkSource: source,
      );
      expect(snapshot.checkDate!.lastCheckedOn, '2024-02-29');
      expect(source.reads, 1);
      source.version = asset.version + 1;
      await expectLater(
        AssetDetailsSnapshot.load(asset, checkSource: source),
        throwsA(isA<Exception>()),
      );
    },
  );
  test('late check date cannot escape an invalidated context', () async {
    final source = CheckSource()..pending = Completer<AssetCheck>();
    var current = true;
    final result = AssetDetailsSnapshot.load(
      AssetRecord.fromJson(record()),
      checkSource: source,
      isCurrent: () => current,
    );
    await Future<void>.delayed(Duration.zero);
    current = false;
    source.pending!.complete(
      const AssetCheck(id: id, version: 1, lastCheckedOn: null),
    );
    await expectLater(result, throwsA(isA<Exception>()));
  });
  testWidgets('details exposes only verified check date to explicit editing', (
    tester,
  ) async {
    AssetCheck? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: AssetDetailsPage(
          record: AssetRecord.fromJson(record()),
          checkSource: CheckSource(),
          onEditCheck: (value) async {
            selected = value;
            return false;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Edit last inventory check'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('2024-02-29'), findsOneWidget);
    await tester.tap(find.text('Edit last inventory check'));
    await tester.pumpAndSettle();
    expect(selected!.lastCheckedOn, '2024-02-29');
    expect(selected!.version, 1);
  });
  testWidgets('mismatched check snapshot never enables editing', (
    tester,
  ) async {
    var edits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AssetDetailsPage(
          record: AssetRecord.fromJson(record()),
          checkSource: CheckSource()..version = 2,
          onEditCheck: (_) async {
            edits++;
            return false;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not verify optional fields'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Edit last inventory check'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Edit last inventory check'),
          )
          .onPressed,
      isNull,
    );
    expect(edits, 0);
    expect(find.text('2024-02-29'), findsNothing);
  });
  test('strict date snapshot preserves exact identity, date and version', () {
    final check = AssetCheck.fromJson(row());
    expect(check.id, id);
    expect(check.lastCheckedOn, '2024-02-29');
    expect(check.replacement(null), {'version': 1, 'lastCheckedOn': null});
    expect(check.replacement('2020-01-01')['lastCheckedOn'], '2020-01-01');
  });
  test('missing and unknown fields never silently become Unknown', () {
    for (final value in [
      row()..remove('lastCheckedOn'),
      {...row(), 'owner': 'other'},
      {...row(), 'version': '1'},
      {...row(), 'id': '../other'},
    ]) {
      expect(() => AssetCheck.fromJson(value), throwsFormatException);
    }
  });
  test('malformed dates and exhausted edit versions are rejected', () {
    for (final date in [
      '',
      '2025-02-29',
      '0000-01-01',
      ' 2024-02-29',
      '2024-02-29T00:00:00Z',
    ]) {
      expect(
        () => AssetCheck.fromJson({...row(), 'lastCheckedOn': date}),
        throwsFormatException,
      );
      expect(
        () => const AssetCheck(
          id: id,
          version: 1,
          lastCheckedOn: null,
        ).replacement(date),
        throwsFormatException,
      );
    }
    expect(
      () => const AssetCheck(
        id: id,
        version: 2147483647,
        lastCheckedOn: null,
      ).replacement(null),
      throwsFormatException,
    );
  });
}

class CheckSource implements AssetCheckSource {
  int reads = 0;
  int version = 1;
  Completer<AssetCheck>? pending;
  @override
  Future<AssetCheck> readCheckDate(String id) async {
    reads++;
    return pending != null
        ? pending!.future
        : AssetCheck(id: id, version: version, lastCheckedOn: '2024-02-29');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected operation');
}

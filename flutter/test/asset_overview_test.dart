import 'package:asset_desk/api/asset_overview.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> summary() => {
  'complete': true,
  'total': 53,
  'byStatus': {'in_use': 0, 'stored': 51, 'repair': 2, 'retired': 0},
  'byCategory': [
    {'category': 'network', 'count': 51},
    {'category': '%_機器', 'count': 2},
  ],
};

void main() {
  test('accepts database-valid 64 astral code points without truncation', () {
    final category = String.fromCharCode(0x1f527) * 64;
    final value = AssetOverview.fromJson({
      ...summary(),
      'byCategory': [
        {'category': category, 'count': 53},
      ],
    });
    expect(value.byCategory.keys.single, category);
    expect(
      () => AssetOverview.fromJson({
        ...summary(),
        'byCategory': [
          {'category': category + 'x', 'count': 53},
        ],
      }),
      throwsFormatException,
    );
  });

  test('validates complete counts and immutable literal category labels', () {
    final value = AssetOverview.fromJson(summary());
    expect(value.total, 53);
    expect(value.byCategory.keys, ['%_機器', 'network']);
    expect(() => value.byCategory['new'] = 1, throwsUnsupportedError);
    expect(() => value.byStatus['stored'] = 0, throwsUnsupportedError);
  });
  test('accepts a truly empty inventory, not missing groups', () {
    final value = AssetOverview.fromJson({
      'complete': true,
      'total': 0,
      'byStatus': {'in_use': 0, 'stored': 0, 'repair': 0, 'retired': 0},
      'byCategory': <Object?>[],
    });
    expect(value.total, 0);
    expect(value.byCategory, isEmpty);
  });
  for (final bad in [null, -1, 1.5, '53', 9007199254740992]) {
    test('rejects invalid total $bad', () {
      expect(
        () => AssetOverview.fromJson({...summary(), 'total': bad}),
        throwsFormatException,
      );
    });
  }
  test('rejects partial, missing, unknown and inconsistent groups', () {
    for (final patch in <Map<String, Object?>>[
      {'complete': false},
      {'byStatus': <String, Object?>{}},
      {
        'byStatus': {
          'in_use': 0,
          'stored': 53,
          'repair': 0,
          'retired': 0,
          'other': 0,
        },
      },
      {'byCategory': <Object?>[]},
      {'total': 52},
      {
        'byCategory': [
          {'category': 'a', 'count': 53},
          {'category': 'a', 'count': 1},
        ],
      },
      {
        'byCategory': [
          {'category': 'a', 'count': 0},
        ],
      },
      {
        'byCategory': [
          {'category': 'a\u0000', 'count': 53},
        ],
      },
      {
        'byCategory': List.generate(201, (i) => {'category': '$i', 'count': 1}),
      },
    ]) {
      expect(
        () => AssetOverview.fromJson({...summary(), ...patch}),
        throwsFormatException,
      );
    }
  });
  test('case-distinct category labels remain distinct', () {
    final value = AssetOverview.fromJson({
      ...summary(),
      'byCategory': [
        {'category': 'Network', 'count': 2},
        {'category': 'network', 'count': 51},
      ],
    });
    expect(value.byCategory.length, 2);
  });
}

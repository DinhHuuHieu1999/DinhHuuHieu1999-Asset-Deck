import 'package:flutter_test/flutter_test.dart';
import 'package:asset_desk/api/asset_saved_filter.dart';

Map<String, Object?> base() => {
  'q': '%_',
  'status': '',
  'category': '',
  'sort': 'updated_desc',
  'locationMode': 'all',
  'location': '',
  'warranty': 'all',
  'asOf': '',
  'checkMode': 'all',
  'checkBefore': '',
  'checkOnOrAfter': '',
};
void main() {
  test('immutable detached query preserves literals', () {
    final input = base();
    final q = AssetSavedFilterQuery.fromJson(input);
    input['q'] = 'changed';
    expect(q.values['q'], '%_');
    expect(() => q.values['q'] = 'x', throwsUnsupportedError);
  });
  test('fixed dates validate leap year without advancing', () {
    final input = base()..addAll({'warranty': 'expired', 'asOf': '2024-02-29'});
    expect(AssetSavedFilterQuery.fromJson(input).values['asOf'], '2024-02-29');
    input['asOf'] = '2023-02-29';
    expect(() => AssetSavedFilterQuery.fromJson(input), throwsFormatException);
  });
  test('reject extra or contradictory fields', () {
    for (final input in [
      base()..['offset'] = 50,
      base()..['checkBefore'] = '2024-01-01',
      base()..['locationMode'] = 'exact',
    ]) {
      expect(
        () => AssetSavedFilterQuery.fromJson(input),
        throwsFormatException,
      );
    }
  });
  test('capability refusal keeps query intact', () {
    final q = AssetSavedFilterQuery.fromJson(base()..['sort'] = 'checked_asc');
    expect(
      () => q.requireCapabilities(location: true, warranty: true, check: false),
      throwsFormatException,
    );
    expect(q.values['sort'], 'checked_asc');
  });
  for (final mode in ['before', 'on_or_after']) {
    test('$mode refuses missing specific capability without losing cutoff', () {
      final field = mode == 'before' ? 'checkBefore' : 'checkOnOrAfter';
      final query = AssetSavedFilterQuery.fromJson(
        base()..addAll({'checkMode': mode, field: '2024-02-29'}),
      );
      expect(
        () => query.requireCapabilities(
          location: true,
          warranty: true,
          check: true,
          checkBefore: mode != 'before',
          checkOnOrAfter: mode != 'on_or_after',
        ),
        throwsFormatException,
      );
      expect(query.values[field], '2024-02-29');
    });
  }
}

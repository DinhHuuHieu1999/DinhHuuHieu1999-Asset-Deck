import 'package:flutter_test/flutter_test.dart';
import '../lib/api/asset_saved_filter.dart';

import '../tool/saved_filters_https_acceptance.dart' show verifySavedDefinition;
import '../tool/client_https_acceptance.dart' show validateDriverArgs;

void main() {
  final query = AssetSavedFilterQuery.fromJson({
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
  });
  AssetSavedFilter record({
    String name = 'View',
    int version = 1,
    String search = '%_',
  }) => AssetSavedFilter.fromJson({
    'id': '11111111-1111-4111-8111-111111111111',
    'name': name,
    'version': version,
    'schemaVersion': 1,
    'query': {...query.values, 'q': search},
  });
  test('round-trip assertion rejects changed names, queries and versions', () {
    verifySavedDefinition(record(), 'View', query, 1);
    for (final bad in [
      record(name: 'Other'),
      record(version: 2),
      record(search: 'other'),
    ]) {
      expect(
        () => verifySavedDefinition(bad, 'View', query, 1),
        throwsStateError,
      );
    }
  });
  test('fixture target validation refuses ordinary or ambiguous endpoints', () {
    for (final url in [
      'http://localhost:29443/api/v1',
      'https://localhost:8443/api/v1',
      'https://example.com:29443/api/v1',
      'https://localhost:29443/api/v1?owner=other',
    ]) {
      expect(
        () => validateDriverArgs(['--synthetic-only', url, 'a' * 32]),
        throwsStateError,
      );
    }
    expect(
      validateDriverArgs([
        '--synthetic-only',
        'https://localhost:29443/api/v1',
        'a' * 32,
      ]).port,
      29443,
    );
  });
}

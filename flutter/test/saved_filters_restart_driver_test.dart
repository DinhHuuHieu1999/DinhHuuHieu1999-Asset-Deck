import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/api/asset_saved_filter.dart';
import '../tool/saved_filters_restart_https_acceptance.dart';

void main() {
  test('restart driver refuses ordinary targets and unknown stages', () {
    final folder = Directory.systemTemp.createTempSync('saved-restart-test-');
    try {
      final args = [
        '--synthetic-only',
        'https://localhost:29443/api/v1',
        'a' * 32,
        'prepare',
        folder.path,
      ];
      expect(validateSavedRestartArgs(args).port, 29443);
      for (final entry in {
        0: 'implicit',
        1: 'https://example.com:29443/api/v1',
        2: 'wrong',
        3: 'other',
        4: 'relative',
      }.entries) {
        final bad = [...args];
        bad[entry.key] = entry.value;
        expect(() => validateSavedRestartArgs(bad), throwsStateError);
      }
    } finally {
      folder.deleteSync();
    }
  });
  test('snapshot retains identity, version and every fixed query field', () {
    final query = <String, Object?>{
      'q': '%_',
      'status': '',
      'category': '',
      'sort': 'checked_asc',
      'locationMode': 'all',
      'location': '',
      'warranty': 'expired',
      'asOf': '2024-02-29',
      'checkMode': 'before',
      'checkBefore': '2024-03-01',
      'checkOnOrAfter': '',
    };
    final json = <String, Object?>{
      'id': '11111111-1111-4111-8111-111111111111',
      'name': 'View',
      'version': 2,
      'schemaVersion': 1,
      'query': query,
    };
    expect(savedRestartSnapshot(AssetSavedFilter.fromJson(json)), json);
  });
}

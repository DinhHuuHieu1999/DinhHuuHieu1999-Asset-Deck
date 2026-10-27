import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/import_v2_recovery_https_acceptance.dart';

void main() {
  late Directory folder;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('asset-recovery-test-');
  });
  // Retain synthetic output; do not recursively remove directories.
  test('stage arguments reject non-fixture endpoints and arbitrary stage', () {
    final args = [
      '--synthetic-only',
      'https://localhost:19003/api/v1',
      'a' * 32,
      Platform.resolvedExecutable,
      'prepare',
      folder.path,
    ];
    expect(validateRecoveryArgs(args).port, 19003);
    for (final bad in [
      <String>[],
      [...args]..[4] = 'automatic',
      [...args]..[1] = 'https://example.com/api/v1',
      [...args]..[5] = 'relative',
    ]) {
      expect(() => validateRecoveryArgs(bad), throwsA(isA<StateError>()));
    }
  });
  test('exclusive save retains existing bytes on second attempt', () async {
    final file = File('${folder.path}/synthetic.json');
    await writeNew(file, '{}');
    await expectLater(
      writeNew(file, '{"changed":true}'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsString(), '{}');
  });
  test('bounded read refuses overflow and invalid UTF-8', () async {
    final file = File('${folder.path}/synthetic.json');
    await file.writeAsString('12345');
    expect(await readBounded(file, 5), '12345');
    await expectLater(readBounded(file, 4), throwsA(isA<StateError>()));
    await file.writeAsBytes([255]);
    await expectLater(readBounded(file, 5), throwsA(isA<FormatException>()));
  });
}

import 'dart:io';

import 'package:asset_desk/main.dart' as entry;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'loopback HTTP opt-in is gated by debug, excluding profile and release',
    () {
      final source = File('lib/main.dart').readAsStringSync();
      expect(
        source,
        contains(
          RegExp(
            r'allowLocalHttp:\s*kDebugMode\s*&&\s*const bool.fromEnvironment\(',
          ),
        ),
      );
      expect(source, isNot(contains('!kReleaseMode')));
    },
  );
  testWidgets(
    'missing endpoint shows configuration guidance, not private inventory',
    (tester) async {
      entry.main();
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Set ASSET_DESK_API_URL to the HTTPS endpoint including /api/v1.',
        ),
        findsOneWidget,
      );
      expect(find.text('Add asset'), findsNothing);
    },
  );
}

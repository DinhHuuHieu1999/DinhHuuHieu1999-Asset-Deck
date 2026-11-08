import 'dart:convert';
import 'dart:io';

import 'package:asset_desk/api/asset_api.dart';
import 'package:asset_desk/api/asset_export.dart';
import 'package:asset_desk/api/asset_import.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late AssetApi api;
  late AssetImportDraft draft;
  late List<String> writes;
  var malformed = false;
  setUp(() async {
    writes = [];
    malformed = false;
    final envelope = jsonDecode(
      File('test/fixtures/inventory-export-v1.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final snapshot = await AssetExport.parse(
      envelope,
      digest: (_) async => envelope['sha256']! as String,
    );
    draft = AssetImportDraft.prepare(
      snapshot: snapshot,
      accountId: 'a' * 24,
      requestId: createAssetImportRequestId(),
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      Object result;
      if (request.uri.path.endsWith('csrf-token')) {
        request.response.cookies.add(Cookie('csrf', 'synthetic'));
        result = {'token': 'synthetic-csrf'};
      } else if (request.uri.path.endsWith('auth/login')) {
        await request.drain<void>();
        result = {
          'accessToken': 'synthetic-token',
          'user': {'id': 'a' * 24, 'name': 'Synthetic'},
        };
      } else {
        expect(request.uri.path, '/api/v1/assets/import');
        expect(
          request.headers.value('authorization'),
          'Bearer synthetic-token',
        );
        expect(request.headers.value('x-csrf-token'), 'synthetic-csrf');
        writes.add(await utf8.decoder.bind(request).join());
        result = {
          'requestId': malformed ? 'wrong' : draft.requestId,
          'recordCount': draft.count,
          'recordIds': [createAssetImportRequestId()],
        };
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(result));
      await request.response.close();
    });
    api = AssetApi(
      Uri.parse('http://127.0.0.1:${server.port}/api/v1'),
      allowLocalHttp: true,
    );
    await api.login('synthetic', 'synthetic-password');
  });
  tearDown(() async {
    api.close();
    await server.close(force: true);
  });
  test('sends the exact draft once with authentication and CSRF', () async {
    final receipt = await api.importInventory(
      draft,
      sessionRevision: api.sessionRevision,
    );
    expect(receipt.requestId, draft.requestId);
    expect(writes, [draft.json]);
  });
  test('rejects a changed session before sending', () async {
    await expectLater(
      api.importInventory(draft, sessionRevision: api.sessionRevision - 1),
      throwsA(
        isA<AssetFailure>().having(
          (e) => e.definitelyNotSent,
          'not sent',
          true,
        ),
      ),
    );
    expect(writes, isEmpty);
  });
  test('rejects another account before sending', () async {
    final envelope = jsonDecode(
      File('test/fixtures/inventory-export-v1.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final other = AssetImportDraft.prepare(
      snapshot: await AssetExport.parse(
        envelope,
        digest: (_) async => envelope['sha256']! as String,
      ),
      accountId: 'b' * 24,
      requestId: createAssetImportRequestId(),
    );
    await expectLater(
      api.importInventory(other, sessionRevision: api.sessionRevision),
      throwsA(isA<AssetFailure>()),
    );
    expect(writes, isEmpty);
  });
  test(
    'malformed receipt is uncertain and does not trigger automatic retry',
    () async {
      malformed = true;
      await expectLater(
        api.importInventory(draft, sessionRevision: api.sessionRevision),
        throwsA(
          isA<AssetFailure>().having(
            (e) => e.definitelyNotSent,
            'uncertain',
            false,
          ),
        ),
      );
      expect(writes, [draft.json]);
    },
  );
}

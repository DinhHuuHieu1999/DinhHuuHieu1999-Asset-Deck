import 'dart:convert';
import 'dart:io';

import 'package:asset_desk/api/asset_api.dart';
import 'package:asset_desk/api/asset_export_v4.dart';

import 'asset_export_v4_test.dart' show exportV4Fixture;

import 'package:asset_desk/api/asset_import.dart'
    show createAssetImportRequestId;
import 'package:asset_desk/api/asset_import_v4.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late AssetApi api;
  late AssetImportV4Draft draft;
  late List<String> writes;
  var malformed = false;
  var unavailable = false;
  setUp(() async {
    writes = [];
    malformed = false;
    unavailable = false;
    final envelope = exportV4Fixture();
    final snapshot = await AssetExportV4.parse(
      envelope,
      digest: (_) async => envelope['sha256']! as String,
    );
    final prepared = AssetImportV4Draft.prepare(
      snapshot: snapshot,
      accountId: 'a' * 24,
      requestId: createAssetImportRequestId(),
    );
    draft = AssetImportV4Draft.restore(
      accountId: prepared.accountId,
      requestJson: ' \n${prepared.json}\t',
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
        expect(request.uri.path, '/api/v1/assets/import/v4');
        expect(
          request.headers.value('authorization'),
          'Bearer synthetic-token',
        );
        expect(request.headers.value('x-csrf-token'), 'synthetic-csrf');
        writes.add(await utf8.decoder.bind(request).join());
        if (unavailable) request.response.statusCode = 503;
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
    final receipt = await api.importInventoryV4(
      draft,
      sessionRevision: api.sessionRevision,
    );
    expect(receipt.requestId, draft.requestId);
    expect(writes, [draft.json]);
  });
  test('rejects a changed session before sending', () async {
    await expectLater(
      api.importInventoryV4(draft, sessionRevision: api.sessionRevision - 1),
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
  test('server failure retains exact operation and never retries', () async {
    unavailable = true;
    final before = draft.json;
    await expectLater(
      api.importInventoryV4(draft, sessionRevision: api.sessionRevision),
      throwsA(
        isA<AssetFailure>().having(
          (error) => error.definitelyNotSent,
          'unknown outcome',
          false,
        ),
      ),
    );
    expect(writes, [before]);
    expect(draft.json, before);
    expect((jsonDecode(before) as Map)['requestId'], draft.requestId);
  });
  test('rejects another account before sending', () async {
    final envelope = exportV4Fixture();
    final other = AssetImportV4Draft.prepare(
      snapshot: await AssetExportV4.parse(
        envelope,
        digest: (_) async => envelope['sha256']! as String,
      ),
      accountId: 'b' * 24,
      requestId: createAssetImportRequestId(),
    );
    await expectLater(
      api.importInventoryV4(other, sessionRevision: api.sessionRevision),
      throwsA(isA<AssetFailure>()),
    );
    expect(writes, isEmpty);
  });
  test(
    'malformed receipt is uncertain and does not trigger automatic retry',
    () async {
      malformed = true;
      await expectLater(
        api.importInventoryV4(draft, sessionRevision: api.sessionRevision),
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

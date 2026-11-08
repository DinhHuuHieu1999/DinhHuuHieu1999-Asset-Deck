import 'dart:convert';
import 'dart:typed_data';

import 'package:asset_desk/api/asset_import_v2.dart';
import 'package:asset_desk/api/asset_import_v2_recovery.dart';
import 'package:asset_desk/api/strict_export_json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const owner = 'abcdef0123456789abcdef01';
  const key = '12345678-1234-4123-8123-123456789abc';
  const api = 'https://localhost:58957/api/v1';
  final checksum = 'a' * 64;
  // Stub tests validation/control flow, not the SHA-256 implementation.
  Future<String> digest(Uint8List bytes) async => checksum;
  final row = <String, Object?>{
    'name': 'Fixture',
    'category': 'test',
    'serial': '%_1',
    'status': 'stored',
    'notes': 'Private',
    'purchasedOn': '2024-02-29',
    'warrantyExpiresOn': null,
  };
  String request({Object? rows, String id = key}) => jsonEncode({
    'requestId': id,
    'records': rows ?? [row],
  });
  AssetImportV2Draft draft() =>
      AssetImportV2Draft.restore(accountId: owner, requestJson: request());
  Future<AssetImportV2Recovery> prepare() => AssetImportV2Recovery.prepare(
    draft: draft(),
    apiBase: api,
    digest: digest,
  );
  Future<AssetImportV2Recovery> parse(
    String source, {
    String target = api,
    String account = owner,
  }) => AssetImportV2Recovery.parse(
    source,
    currentApiBase: target,
    currentAccountId: account,
    digest: digest,
  );
  test(
    'round trip exact JSON/key and digest payload; deeply immutable',
    () async {
      Uint8List? hashed;
      final r = await AssetImportV2Recovery.prepare(
        draft: draft(),
        apiBase: api,
        digest: (bytes) async {
          hashed = bytes;
          return checksum;
        },
      );
      expect(utf8.decode(hashed!), (jsonDecode(r.json) as Map)['payload']);
      final restored = await parse(r.json);
      expect(restored.draft.json, request());
      expect(restored.draft.requestId, key);
      expect(restored.draft.accountId, owner);
      expect(
        () => restored.draft.records.first['name'] = 'x',
        throwsUnsupportedError,
      );
    },
  );
  test('wrong endpoint rejected before digest', () async {
    var calls = 0;
    final r = await prepare();
    await expectLater(
      AssetImportV2Recovery.parse(
        r.json,
        currentApiBase: 'https://other.invalid/api/v1',
        currentAccountId: owner,
        digest: (_) async {
          calls++;
          return checksum;
        },
      ),
      throwsFormatException,
    );
    expect(calls, 0);
  });
  test('wrong account refused', () async {
    await expectLater(
      parse((await prepare()).json, account: '123456789012345678901234'),
      throwsStateError,
    );
  });
  test('checksum mismatch refused', () async {
    await expectLater(
      AssetImportV2Recovery.parse(
        (await prepare()).json,
        currentApiBase: api,
        currentAccountId: owner,
        digest: (_) async => 'b' * 64,
      ),
      throwsFormatException,
    );
  });
  test('outer and payload duplicate keys refused', () async {
    final e = jsonDecode((await prepare()).json) as Map<String, dynamic>;
    await expectLater(
      parse('{"format":"duplicate",${jsonEncode(e).substring(1)}'),
      throwsFormatException,
    );
    e['payload'] =
        '{"apiBase":"$api","apiBase":"$api","accountId":"$owner","requestJson":${jsonEncode(request())}}';
    await expectLater(parse(jsonEncode(e)), throwsFormatException);
  });
  test('credentials and completion metadata refused', () async {
    for (final field in ['token', 'completed', 'notSent']) {
      final e = jsonDecode((await prepare()).json) as Map<String, dynamic>;
      final p = jsonDecode(e['payload'] as String) as Map;
      p[field] = 'forbidden';
      e['payload'] = jsonEncode(p);
      await expectLater(parse(jsonEncode(e)), throwsFormatException);
    }
  });
  test('unsafe endpoints refused', () async {
    for (final url in [
      'https://u:p@localhost/api/v1',
      '$api?key=x',
      '$api#x',
      '/api/v1',
      'file:///api/v1',
    ]) {
      await expectLater(
        AssetImportV2Recovery.prepare(
          draft: draft(),
          apiBase: url,
          digest: digest,
        ),
        throwsFormatException,
      );
    }
  });
  test('identity duplicate keys and malformed Unicode refused', () {
    expect(
      () =>
          AssetImportV2Draft.restore(accountId: 'bad', requestJson: request()),
      throwsFormatException,
    );
    expect(
      () => AssetImportV2Draft.restore(
        accountId: owner,
        requestJson: request(id: 'bad'),
      ),
      throwsFormatException,
    );
    expect(
      () => AssetImportV2Draft.restore(
        accountId: owner,
        requestJson: '{"requestId":"$key",${request().substring(1)}',
      ),
      throwsFormatException,
    );
    expect(
      () => AssetImportV2Draft.restore(
        accountId: owner,
        requestJson: request().replaceFirst('Private', r'\ud800'),
      ),
      throwsFormatException,
    );
  });
  test('invalid fields and record bounds refused', () {
    for (final rows in [
      <Object?>[],
      List.filled(501, row),
      [
        {...row, 'owner': owner},
      ],
      [
        {...row, 'name': '  Fixture'},
      ],
      [
        {...row, 'status': 'unknown'},
      ],
      [
        {...row, 'notes': 'x' * 2001},
      ],
      [
        {...row, 'serial': '\u0000'},
      ],
    ]) {
      expect(
        () => AssetImportV2Draft.restore(
          accountId: owner,
          requestJson: request(rows: rows),
        ),
        throwsFormatException,
      );
    }
  });
  test('separate outer and request byte limits', () async {
    await expectLater(
      parse(' ' * (AssetImportV2Recovery.maxBytes + 1)),
      throwsFormatException,
    );
    expect(
      () => AssetImportV2Draft.restore(
        accountId: owner,
        requestJson: ' ' * (1024 * 1024 + 1),
      ),
      throwsFormatException,
    );
    expect(
      () => decodeAssetExportJson(' ' * (1024 * 1024 + 1)),
      throwsFormatException,
    );
  });
  test('invalid digest and envelope refused', () async {
    await expectLater(
      AssetImportV2Recovery.prepare(
        draft: draft(),
        apiBase: api,
        digest: (_) async => 'invalid',
      ),
      throwsFormatException,
    );
    for (final json in ['null', '[]', '{}', '{"schemaVersion":true}']) {
      await expectLater(parse(json), throwsFormatException);
    }
  });
  test('500 records round-trip without changing request identity', () async {
    final raw = request(rows: List.filled(500, row));
    final source = AssetImportV2Draft.restore(
      accountId: owner,
      requestJson: raw,
    );
    final recovery = await AssetImportV2Recovery.prepare(
      draft: source,
      apiBase: api,
      digest: digest,
    );
    final restored = await parse(recovery.json);
    expect(restored.draft.count, 500);
    expect(restored.draft.json, raw);
    expect(restored.draft.requestId, key);
  });
  test(
    'valid escaped payload above 1 MiB uses separate recovery bound',
    () async {
      final expanded = {...row, 'notes': '${'x' * 1300}${'\\' * 350}'};
      final raw = request(rows: List.filled(400, expanded));
      expect(utf8.encode(raw).length, lessThan(1024 * 1024));
      final recovery = await AssetImportV2Recovery.prepare(
        draft: AssetImportV2Draft.restore(accountId: owner, requestJson: raw),
        apiBase: api,
        digest: digest,
      );
      final payload = (jsonDecode(recovery.json) as Map)['payload'] as String;
      expect(utf8.encode(payload).length, greaterThan(1024 * 1024));
      expect(
        utf8.encode(recovery.json).length,
        lessThanOrEqualTo(2 * 1024 * 1024),
      );
      expect((await parse(recovery.json)).draft.json, raw);
    },
  );
  test('request whitespace preserved exactly', () {
    final raw = '  ${request()}\n';
    expect(
      AssetImportV2Draft.restore(accountId: owner, requestJson: raw).json,
      raw,
    );
  });
}

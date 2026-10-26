import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:asset_desk/api/asset_api.dart';
import 'package:asset_desk/api/asset.dart';
import 'package:asset_desk/api/asset_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'asset_test.dart' show record;

void main() {
  for (final url in [
    'http://example.com/api/v1',
    'http://localhost/api/v1',
    'https://user:secret@example.com/api/v1',
    'https://example.com/api/v1?q=x',
    'https://example.com/api/v1#x',
    'https://example.com/other',
    'file:///api/v1',
  ]) {
    test('rejects endpoint $url', () {
      expect(() => AssetApi(Uri.parse(url)), throwsArgumentError);
    });
  }
  test('debug HTTP opt-in is limited to explicit loopback', () {
    expect(
      () => AssetApi(
        Uri.parse('http://192.168.0.2/api/v1'),
        allowLocalHttp: true,
      ),
      throwsArgumentError,
    );
    final api = AssetApi(Uri.parse('https://example.com/api/v1'));
    expect(api.baseUrl.path, '/api/v1/');
    api.close();
    expect(
      () => AssetApi(
        Uri.parse('https://example.com/api/v1'),
        timeout: Duration.zero,
      ),
      throwsArgumentError,
    );
  });

  group('isolated synthetic HTTP transport, no product backend', () {
    late HttpServer server;
    late AssetApi api;
    late Future<void> Function(HttpRequest) handler;
    late List<String> calls;
    late List<Object> handlerErrors;
    var csrfCount = 0;
    Future<Map<String, Object?>> body(HttpRequest request) async =>
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, Object?>;
    void json(HttpRequest request, Object response, {int status = 200}) {
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
    }

    Future<void> defaultHandler(HttpRequest request) async {
      if (request.uri.path.endsWith('/csrf-token')) {
        csrfCount++;
        request.response.cookies.add(Cookie('csrf_token', 'synthetic-cookie'));
        json(request, {'token': 'synthetic-csrf'});
      } else if (request.uri.path.endsWith('/auth/login') ||
          request.uri.path.endsWith('/auth/register')) {
        final input = await body(request);
        expect(request.headers.value('x-csrf-token'), 'synthetic-csrf');
        expect(request.cookies.single.value, 'synthetic-cookie');
        expect(input['password'], ' synthetic-pass ');
        json(request, {
          'accessToken': 'synthetic-token',
          'user': {'id': 'a' * 24, 'name': 'Synthetic'},
        });
      } else if (request.method == 'GET') {
        json(request, {
          'items': [record()],
          'nextOffset': null,
        });
      } else {
        final input = await body(request);
        json(request, {
          ...record(),
          ...input,
          'version': request.method == 'PUT' ? 2 : 1,
        });
      }
    }

    setUp(() async {
      calls = [];
      handlerErrors = [];
      csrfCount = 0;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      handler = defaultHandler;
      server.listen((request) async {
        calls.add('${request.method} ${request.uri.path}');
        try {
          await handler(request);
          await request.response.close();
        } on IOException {
          /* A deliberately cancelled client may close first. */
        } catch (error) {
          handlerErrors.add(error);
          request.response.statusCode = 500;
          await request.response.close();
        }
      });
      api = AssetApi(
        Uri.parse('http://127.0.0.1:${server.port}/api/v1'),
        allowLocalHttp: true,
      );
    });
    tearDown(() async {
      api.close();
      await server.close(force: true);
      expect(handlerErrors, isEmpty);
    });
    Future<void> login() => api.login(' synthetic ', ' synthetic-pass ');

    test(
      'login, cookie/header timestamp and literal query are preserved',
      () async {
        await login();
        expect(api.account!.id, 'a' * 24);
        handler = (request) async {
          expect(
            request.headers.value('authorization'),
            'Bearer synthetic-token',
          );
          expect(
            int.tryParse(request.headers.value('x-request-timestamp')!),
            isNotNull,
          );
          expect(request.uri.queryParameters, {
            'q': '%_ &?#',
            'status': 'stored',
            'offset': '0',
          });
          json(request, {
            'items': [record()],
            'nextOffset': null,
          });
        };
        final result = await api.list(
          query: '%_ &?#',
          status: 'stored',
          offset: 0,
        );
        expect(result.items.single.input.name, 'Laptop');
        expect(csrfCount, 1);
      },
    );
    test(
      'category is trimmed and encoded literally with other filters',
      () async {
        await login();
        handler = (request) async {
          expect(request.uri.queryParameters, {
            'q': 'router',
            'status': 'stored',
            'category': '%_ &?#',
            'offset': '50',
          });
          json(request, {'items': <Object?>[], 'nextOffset': null});
        };
        await api.list(
          query: 'router',
          status: 'stored',
          category: '  %_ &?#  ',
          offset: 50,
        );
        final before = calls.length;
        for (final value in ['x' * 65, 'bad\u0000category']) {
          await expectLater(
            api.list(query: '', status: '', category: value, offset: 0),
            throwsA(isA<AssetFailure>()),
          );
        }
        expect(calls.length, before);
      },
    );
    test(
      'register sends only public fields and accepts valid identity',
      () async {
        await api.register(
          email: ' synthetic@example.com ',
          username: ' synthetic ',
          name: ' Synthetic ',
          password: ' synthetic-pass ',
        );
        expect(api.account!.name, 'Synthetic');
        expect(calls.last, 'POST /api/v1/auth/register');
      },
    );
    Map<String, Object?> exportFixture() => jsonDecode(
      File('test/fixtures/inventory-export-v1.json').readAsStringSync(),
    ) as Map<String, Object?>;

    test(
      'exports through dedicated authenticated endpoint without list filters',
      () async {
        await login();
        final fixture = exportFixture();
        handler = (request) async {
          expect(request.method, 'GET');
          expect(request.uri.path, '/api/v1/assets/export');
          expect(request.uri.hasQuery, isFalse);
          expect(
            request.headers.value('authorization'),
            'Bearer synthetic-token',
          );
          json(request, fixture);
        };
        final before = calls.length;
        final result = await api.exportInventory(
          digest: (_) async => fixture['sha256']! as String,
        );
        expect(result.count, 1);
        expect(calls.length, before + 1);
        expect(csrfCount, 1);
      },
    );

    test('anonymous export never requests data or digest', () async {
      await expectLater(
        api.exportInventory(
          digest: (_) async => throw StateError('must not run'),
        ),
        throwsA(isA<AssetFailure>()),
      );
      expect(calls, isEmpty);
    });

    test('sign-out during digest rejects late prepared export', () async {
      await login();
      final fixture = exportFixture();
      handler = (request) async => json(request, fixture);
      final entered = Completer<void>();
      final release = Completer<String>();
      final result = api.exportInventory(
        digest: (_) {
          entered.complete();
          return release.future;
        },
      );
      final assertion = expectLater(result, throwsA(isA<AssetFailure>()));
      await entered.future;
      api.signOut();
      release.complete(fixture['sha256']! as String);
      await assertion;
      expect(api.account, isNull);
    });

    for (final status in [401, 422, 500]) {
      test('export failure $status is explicit and is never retried', () async {
        await login();
        handler = (request) async => json(request, {}, status: status);
        final before = calls.length;
        await expectLater(
          api.exportInventory(
            digest: (_) async => throw StateError('must not run'),
          ),
          throwsA(
            isA<AssetFailure>().having((e) => e.statusCode, 'status', status),
          ),
        );
        expect(calls.length, before + 1);
        expect(api.account == null, status == 401);
      });
    }

    test(
      'invalid export checksum returns a safe failure without retry',
      () async {
        await login();
        handler = (request) async => json(request, exportFixture());
        final before = calls.length;
        await expectLater(
          api.exportInventory(digest: (_) async => '0' * 64),
          throwsA(
            isA<AssetFailure>().having(
              (e) => e.message,
              'message',
              contains('checksum'),
            ),
          ),
        );
        expect(calls.length, before + 1);
      },
    );

    test('anonymous and invalid inputs make no request', () async {
      await expectLater(
        api.list(query: '', status: '', offset: 0),
        throwsA(isA<AssetFailure>()),
      );
      await expectLater(api.login('x', 'short'), throwsA(isA<AssetFailure>()));
      await expectLater(
        api.register(email: 'bad', username: 'x', name: '', password: 'short'),
        throwsA(isA<AssetFailure>()),
      );
      expect(calls, isEmpty);
    });
    test(
      'create/update serialize editable fields and optimistic version only',
      () async {
        await login();
        const input = AssetInput(
          name: ' Router ',
          category: ' Network ',
          status: 'stored',
        );
        final created = await api.create(input);
        expect(created.input.name, 'Router');
        final updated = await api.update(created, input);
        expect(updated.version, 2);
        expect(csrfCount, 1);
        expect(
          calls.where((c) => c.startsWith('POST /api/v1/assets')),
          hasLength(1),
        );
      },
    );
    test(
      'reject invalid page/query and metadata without automatic retry',
      () async {
        await login();
        final before = calls.length;
        await expectLater(
          api.list(query: 'x' * 121, status: '', offset: 0),
          throwsA(isA<AssetFailure>()),
        );
        expect(calls.length, before);
        handler = (request) async => json(request, {
          'items': [record()],
          'nextOffset': 50,
        });
        await expectLater(
          api.list(query: '', status: '', offset: 0),
          throwsA(isA<AssetFailure>()),
        );
        expect(calls.length, before + 1);
      },
    );
    for (final status in [400, 403, 409, 422, 429, 503]) {
      test(
        'HTTP $status returns bounded safe failure and makes one write',
        () async {
          await login();
          handler = (request) async => json(request, {
            'message': 'PRIVATE SERVER DETAIL',
          }, status: status);
          final before = calls.length;
          await expectLater(
            api.create(
              const AssetInput(name: 'A', category: 'B', status: 'stored'),
            ),
            throwsA(
              isA<AssetFailure>()
                  .having((e) => e.statusCode, 'status', status)
                  .having(
                    (e) => e.message.contains('PRIVATE'),
                    'does not echo private body',
                    false,
                  ),
            ),
          );
          expect(calls.length, before + 1);
        },
      );
    }
    test('401 invalidates the account and discards bearer/cookies', () async {
      await login();
      final oldRevision = api.sessionRevision;
      handler = (request) async => json(request, {}, status: 401);
      await expectLater(
        api.list(query: '', status: '', offset: 0),
        throwsA(isA<AssetFailure>()),
      );
      expect(api.account, isNull);
      expect(api.sessionRevision, greaterThan(oldRevision));
      handler = (request) async {
        if (request.uri.path.endsWith('/csrf-token')) {
          expect(request.headers.value('authorization'), isNull);
          expect(request.cookies, isEmpty);
        }
        await defaultHandler(request);
      };
      await login();
      expect(csrfCount, 2);
    });
    test('sign-out discards a late inventory response', () async {
      await login();
      final entered = Completer<void>(), release = Completer<void>();
      handler = (request) async {
        entered.complete();
        await release.future;
        json(request, {
          'items': [record()],
          'nextOffset': null,
        });
      };
      final pending = api.list(query: '', status: '', offset: 0);
      final assertion = expectLater(pending, throwsA(isA<AssetFailure>()));
      await entered.future;
      api.signOut();
      release.complete();
      await assertion;
      expect(api.account, isNull);
    });
    test('sign-out prevents a late login from restoring account', () async {
      final entered = Completer<void>(), release = Completer<void>();
      handler = (request) async {
        if (request.uri.path.endsWith('/auth/login')) {
          entered.complete();
          await release.future;
        }
        await defaultHandler(request);
      };
      final pending = login();
      final assertion = expectLater(pending, throwsA(isA<AssetFailure>()));
      await entered.future;
      api.signOut();
      release.complete();
      await assertion;
      expect(api.account, isNull);
    });
    test('new account wins over an older pending sign-in', () async {
      final entered = Completer<void>(), release = Completer<void>();
      handler = (request) async {
        if (request.uri.path.endsWith('/auth/login')) {
          final input = await body(request);
          if (input['identifier'] == 'older') {
            entered.complete();
            await release.future;
          }
          final newer = input['identifier'] == 'newer';
          json(request, {
            'accessToken': newer ? 'new-token' : 'old-token',
            'user': {
              'id': (newer ? 'b' : 'a') * 24,
              'name': newer ? 'New owner' : 'Old owner',
            },
          });
        } else {
          await defaultHandler(request);
        }
      };
      final old = api.login('older', 'synthetic-pass');
      final oldAssertion = expectLater(old, throwsA(isA<AssetFailure>()));
      await entered.future;
      await api.login('newer', 'synthetic-pass');
      release.complete();
      await oldAssertion;
      expect(api.account!.id, 'b' * 24);
      handler = (request) async {
        expect(request.headers.value('authorization'), 'Bearer new-token');
        json(request, {'items': <Object?>[], 'nextOffset': null});
      };
      await api.list(query: '', status: '', offset: 0);
    });

    test('malformed auth response cannot create an account', () async {
      handler = (request) async {
        if (request.uri.path.endsWith('/csrf-token')) {
          await defaultHandler(request);
          return;
        }
        json(request, {
          'accessToken': 'token',
          'user': {'id': 'not-an-id', 'name': 'Bad'},
        });
      };
      await expectLater(login(), throwsA(isA<AssetFailure>()));
      expect(api.account, isNull);
    });
    test('invalid CSRF stops before sending credentials', () async {
      handler = (request) async => json(request, {'token': ''});
      await expectLater(login(), throwsA(isA<AssetFailure>()));
      expect(calls, ['GET /api/v1/csrf-token']);
    });
    for (final secureCookie in [false, true]) {
      test(
        secureCookie
            ? 'debug HTTP cannot downgrade a secure CSRF cookie'
            : 'valid token without cookie cannot send credentials',
        () async {
          handler = (request) async {
            if (secureCookie) {
              request.response.cookies.add(
                Cookie('csrf_token', 'synthetic-cookie')..secure = true,
              );
            }
            json(request, {'token': 'synthetic-csrf'});
          };
          await expectLater(login(), throwsA(isA<AssetFailure>()));
          expect(calls, ['GET /api/v1/csrf-token']);
          expect(api.account, isNull);
        },
      );
    }
    for (final mode in ['redirect', 'wrong-type', 'malformed', 'oversize']) {
      test('rejects $mode response', () async {
        await login();
        handler = (request) async {
          switch (mode) {
            case 'redirect':
              request.response.statusCode = 302;
              request.response.headers.set('location', '/must-not-follow');
            case 'wrong-type':
              request.response.headers.contentType = ContentType.html;
              request.response.write('{}');
            case 'malformed':
              request.response.headers.contentType = ContentType.json;
              request.response.write('[');
            case 'oversize':
              request.response.headers.contentType = ContentType.json;
              request.response.write('x' * (1024 * 1024 + 1));
          }
        };
        final before = calls.length;
        await expectLater(
          api.list(query: '', status: '', offset: 0),
          throwsA(isA<AssetFailure>()),
        );
        expect(calls.length, before + 1);
      });
    }
    test('deadline ends stalled response, close is idempotent', () async {
      api.close();
      api = AssetApi(
        Uri.parse('http://127.0.0.1:${server.port}/api/v1'),
        allowLocalHttp: true,
        timeout: const Duration(milliseconds: 300),
      );
      final release = Completer<void>();
      handler = (request) async {
        await release.future;
        json(request, {});
      };
      await expectLater(
        login(),
        throwsA(
          isA<AssetFailure>().having(
            (e) => e.message,
            'timeout',
            'Request timed out',
          ),
        ),
      );
      release.complete();
      api.close();
      api.close();
      await expectLater(login(), throwsA(isA<AssetFailure>()));
    });
  });
}

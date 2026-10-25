import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/native_https_seed.dart' as seed;

class MarkerResponse extends Stream<List<int>> implements HttpClientResponse {
  MarkerResponse(this.statusCode, this.bytes);
  @override
  final int statusCode;
  final List<int> bytes;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MarkerRequest implements HttpClientRequest {
  MarkerRequest(this.response);
  final MarkerResponse response;
  @override
  bool followRedirects = true;
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MarkerClient implements HttpClient {
  MarkerClient(this.request);
  final MarkerRequest request;
  Uri? requested;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested = url;
    return request;
  }

  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final endpoint = Uri.parse('https://localhost:19003/api/v1');
  test('native marker uses exact identity and refuses redirects', () async {
    final client = MarkerClient(
      MarkerRequest(
        MarkerResponse(
          200,
          utf8.encode(jsonEncode({'fixtureId': id, 'syntheticOnly': true})),
        ),
      ),
    );
    await seed.verifyNativeMarker(client, endpoint, id);
    expect(
      client.requested.toString(),
      'https://localhost:19003/__asset_desk_fixture/$id',
    );
    expect(client.request.followRedirects, isFalse);
  });
  test(
    'native marker refuses wrong identity, malformed and oversized data',
    () async {
      for (final bytes in [
        utf8.encode(jsonEncode({'fixtureId': 'wrong', 'syntheticOnly': true})),
        utf8.encode('not json'),
        List<int>.filled(1025, 32),
      ]) {
        final client = MarkerClient(MarkerRequest(MarkerResponse(200, bytes)));
        await expectLater(
          seed.verifyNativeMarker(client, endpoint, id),
          throwsA(anything),
        );
      }
    },
  );
  test('native marker refuses HTTP error and redirect responses', () async {
    for (final status in [301, 403, 500]) {
      final client = MarkerClient(MarkerRequest(MarkerResponse(status, [])));
      await expectLater(
        seed.verifyNativeMarker(client, endpoint, id),
        throwsStateError,
      );
    }
  });
  test('invalid native seed args never contact the network', () async {
    final client = MarkerClient(MarkerRequest(MarkerResponse(200, [])));
    final previousExitCode = exitCode;
    try {
      await HttpOverrides.runZoned(
        () => seed.main([
          '--synthetic-only',
          'https://example.com:19003/api/v1',
          id,
        ]),
        createHttpClient: (_) => client,
      );
      expect(exitCode, 1);
      expect(client.requested, isNull);
    } finally {
      exitCode = previousExitCode;
    }
  });
}

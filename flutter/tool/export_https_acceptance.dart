import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../lib/api/asset.dart';
import '../lib/api/asset_api.dart';
import 'client_https_acceptance.dart' show check, validateDriverArgs;
import 'native_https_seed.dart' show verifyNativeMarker;

/// Fixture-only bridge output; never accept a missing or malformed digest.
String parseDigestOutput(List<int> bytes) {
  check(bytes.length == 65);
  final value = utf8.decode(bytes);
  check(RegExp(r'^[0-9a-f]{64}\n$').hasMatch(value));
  return value.substring(0, 64);
}

/// Require an explicit local executable; no shell or PATH discovery in the driver.
void validatePython(String executable) {
  check(File(executable).isAbsolute && FileSystemEntity.isFileSync(executable));
}

/// Fixture-only SHA-256 oracle. Production uses Windows CNG, not a subprocess.
Future<String> pythonDigest(String executable, Uint8List bytes) async {
  check(bytes.length <= 1024 * 1024);
  validatePython(executable);
  final child = await Process.start(executable, [
    '-c',
    'import hashlib,sys; b=sys.stdin.buffer.read(1048577); '
        'sys.exit(2) if len(b)>1048576 else '
        'sys.stdout.buffer.write(hashlib.sha256(b).hexdigest().encode()+bytes([10]))',
  ]);
  Future<List<int>> collect(Stream<List<int>> stream, int limit) async {
    final result = <int>[];
    await for (final chunk in stream) {
      check(result.length + chunk.length <= limit);
      result.addAll(chunk);
    }
    return result;
  }

  try {
    // Subscribe before writing; Future.wait observes every stream/process error.
    final completion = Future.wait<Object>([
      collect(child.stdout, 65),
      collect(child.stderr, 1024),
      child.exitCode,
      (() async {
        child.stdin.add(bytes);
        await child.stdin.close();
        return true;
      })(),
    ], eagerError: true);
    final result = await completion.timeout(const Duration(seconds: 10));
    check(result[2] == 0 && (result[1] as List<int>).isEmpty);
    return parseDigestOutput(result[0] as List<int>);
  } finally {
    child.kill();
    await child.exitCode.timeout(
      const Duration(seconds: 2),
      onTimeout: () => -1,
    );
  }
}

/// Actual Dart API/parser against a marker-owned synthetic HTTPS fixture only.
Future<void> main(List<String> args) async {
  final clients = <AssetApi>[];
  final probe = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    check(args.length == 4);
    final endpoint = validateDriverArgs(args.sublist(0, 3));
    validatePython(args[3]);
    await verifyNativeMarker(probe, endpoint, args[2]);
    final suffix = List.generate(
      12,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final a = AssetApi(endpoint), b = AssetApi(endpoint);
    clients.addAll([a, b]);
    for (final entry in [('a', a), ('b', b)]) {
      await entry.$2.register(
        email: '${entry.$1}$suffix@example.invalid',
        username: '${entry.$1}$suffix',
        name: 'Synthetic export client',
        password: 'Synthetic-$suffix-42!',
      );
    }
    Future<String> digest(Uint8List bytes) => pythonDigest(args[3], bytes);
    check((await a.exportInventory(digest: digest)).count == 0);
    for (var i = 0; i < 51; i++) {
      await a.create(
        AssetInput(
          name: 'Synthetic Dart export $i',
          category: 'fixture',
          serial: 'SERIAL-%_$i',
          status: 'stored',
          notes: 'Synthetic Unicode \u00e9\u4e2d\u{1f680}',
        ),
      );
    }
    final snapshot = await a.exportInventory(digest: digest);
    check(
      snapshot.count == 51 &&
          snapshot.records.map((r) => r.id).toSet().length == 51,
    );
    check(
      snapshot.records.every(
        (r) => r.input.notes == 'Synthetic Unicode \u00e9\u4e2d\u{1f680}',
      ),
    );
    check((await b.exportInventory(digest: digest)).count == 0);
    check(
      (await a.list(
        query: 'missing',
        status: 'retired',
        offset: 0,
      )).items.isEmpty,
    );
    check((await a.exportInventory(digest: digest)).count == 51);
    stdout.writeln(
      jsonEncode({
        'status': 'completed',
        'syntheticOnly': true,
        'owners': 2,
        'assetCount': 51,
        'digest': 'python-sha256-stdin',
        'nativeDialog': 'not-exercised',
      }),
    );
  } catch (_) {
    stderr.writeln(
      'Synthetic Dart export acceptance failed; no automatic retry.',
    );
    exitCode = 1;
  } finally {
    probe.close(force: true);
    for (final client in clients) {
      client.close();
    }
  }
}

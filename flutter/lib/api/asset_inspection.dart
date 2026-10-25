import 'dart:convert';
import 'dart:typed_data';

import 'asset_export.dart';
import 'strict_export_json.dart';

/// Inspect an untrusted local file without backend access or persistent state.
/// The caller must obtain bytes through an explicit, bounded file selection.
Future<AssetExport> inspectAssetBytes(
  Uint8List bytes, {
  required AssetExportDigest digest,
}) async {
  if (bytes.length < 2 || bytes.length > 1024 * 1024) {
    throw const FormatException(
      'Inventory JSON must be between 2 bytes and 1 MiB',
    );
  }
  if (bytes.length >= 3 &&
      bytes[0] == 239 &&
      bytes[1] == 187 &&
      bytes[2] == 191) {
    throw const FormatException('Choose UTF-8 JSON without a byte-order mark');
  }
  final value = decodeAssetExportJson(
    utf8.decode(bytes, allowMalformed: false),
  );
  if (value is! Map<String, Object?>) {
    throw const FormatException('Inventory JSON must contain an export object');
  }
  return AssetExport.parse(value, digest: digest);
}

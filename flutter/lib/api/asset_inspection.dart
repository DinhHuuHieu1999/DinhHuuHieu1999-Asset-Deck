import 'dart:convert';
import 'dart:typed_data';

import 'asset_export.dart';
import 'asset_export_v3.dart';
import 'asset_selection_export.dart';
import 'strict_export_json.dart';

/// Inspect an untrusted local file without backend access or persistent state.
/// The caller must obtain bytes through an explicit, bounded file selection.
Future<AssetExport> inspectAssetBytes(
  Uint8List bytes, {
  required AssetExportDigest digest,
}) async {
  final value = _decodeInspectionBytes(bytes);
  return AssetExport.parse(value, digest: digest);
}

/// Read-only v3 inspection; never converts schemas or calls an import client.
Future<AssetExportV3> inspectAssetV3Bytes(
  Uint8List bytes, {
  required AssetExportDigest digest,
}) async {
  final value = _decodeInspectionBytes(bytes);
  return AssetExportV3.parse(value, digest: digest);
}

/// Inspect a filtered selection without importing or accessing a backend.
Future<AssetSelectionExport> inspectAssetSelectionBytes(
  Uint8List bytes, {
  required AssetExportDigest digest,
}) async {
  return AssetSelectionExport.parse(
    _decodeInspectionBytes(bytes),
    digest: digest,
  );
}

Map<String, Object?> _decodeInspectionBytes(Uint8List bytes) {
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
  return value;
}

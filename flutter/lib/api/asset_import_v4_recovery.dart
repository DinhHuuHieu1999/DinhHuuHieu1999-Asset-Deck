import 'dart:convert';
import 'dart:typed_data';

import 'asset_export.dart';
import 'asset_import_v4.dart';
import 'strict_export_json.dart';

/// Private plaintext operation file; checksum is not proof of authenticity.
class AssetImportV4Recovery {
  AssetImportV4Recovery._(this.json, this.apiBase, this.draft);
  final String json;
  final String apiBase;
  final AssetImportV4Draft draft;
  static const maxBytes = 2 * 1024 * 1024;

  static void _endpoint(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path.isEmpty ||
        value.trim() != value) {
      throw const FormatException('Invalid recovery API base');
    }
  }

  /// Serialize an exact immutable operation without credentials or disk writes.
  static Future<AssetImportV4Recovery> prepare({
    required AssetImportV4Draft draft,
    required String apiBase,
    required AssetExportDigest digest,
  }) async {
    _endpoint(apiBase);
    final validated = AssetImportV4Draft.restore(
      accountId: draft.accountId,
      requestJson: draft.json,
    );
    final payload = jsonEncode({
      'apiBase': apiBase,
      'accountId': validated.accountId,
      'operation': 'inventory-add-only-v4',
      'requestJson': validated.json,
    });
    // Bound the payload independently; the retained request has its own 1 MiB cap.
    if (utf8.encode(payload).length > maxBytes) {
      throw const FormatException('Recovery payload exceeds 2 MiB');
    }
    final checksum = await digest(Uint8List.fromList(utf8.encode(payload)));
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum)) {
      throw const FormatException('Invalid recovery checksum result');
    }
    final json = jsonEncode({
      'format': 'asset-desk-import-recovery',
      'schemaVersion': 4,
      'payload': payload,
      'sha256': checksum,
    });
    if (utf8.encode(json).length > maxBytes) {
      throw const FormatException('Recovery file exceeds 2 MiB');
    }
    return AssetImportV4Recovery._(json, apiBase, validated);
  }

  /// Validate before review; never contact or adopt the file-supplied endpoint.
  static Future<AssetImportV4Recovery> parse(
    String json, {
    required String currentApiBase,
    required String currentAccountId,
    required AssetExportDigest digest,
  }) async {
    _endpoint(currentApiBase);
    final envelope = decodeAssetRecoveryJson(json);
    if (envelope is! Map<String, Object?> ||
        envelope.length != 4 ||
        envelope['format'] != 'asset-desk-import-recovery' ||
        envelope['schemaVersion'] is! int ||
        envelope['schemaVersion'] != 4 ||
        envelope['payload'] is! String ||
        envelope['sha256'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(envelope['sha256']! as String)) {
      throw const FormatException('Invalid recovery envelope');
    }
    final payload = envelope['payload']! as String;
    final decoded = decodeAssetRecoveryJson(payload);
    if (decoded is! Map<String, Object?> ||
        decoded.length != 4 ||
        decoded['apiBase'] != currentApiBase ||
        decoded['operation'] != 'inventory-add-only-v4' ||
        decoded['accountId'] is! String ||
        decoded['requestJson'] is! String) {
      throw const FormatException('Recovery target does not match');
    }
    final draft = AssetImportV4Draft.restore(
      accountId: decoded['accountId']! as String,
      requestJson: decoded['requestJson']! as String,
    );
    draft.requireAccount(currentAccountId);
    final actual = await digest(Uint8List.fromList(utf8.encode(payload)));
    if (actual != envelope['sha256']) {
      throw const FormatException('Recovery checksum mismatch');
    }
    return AssetImportV4Recovery._(json, currentApiBase, draft);
  }
}

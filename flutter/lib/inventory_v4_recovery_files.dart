import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'api/asset_import_v4_recovery.dart';
import 'api/asset_store.dart';

/// Explicit private recovery file boundary; never accepts a filesystem path.
abstract interface class InventoryV4RecoveryFiles {
  Future<String> digest(Uint8List bytes);
  Future<bool> save(AssetImportV4Recovery recovery);
  Future<Uint8List?> choose();
}

/// Recovery-only native methods retain export and Inspect's existing limits.
class WindowsInventoryV4RecoveryFiles implements InventoryV4RecoveryFiles {
  static const _channel = MethodChannel('asset_desk/inventory_export');

  @override
  Future<String> digest(Uint8List bytes) async {
    if (bytes.length > AssetImportV4Recovery.maxBytes) {
      throw const AssetFailure('Recovery payload exceeds 2 MiB');
    }
    try {
      final value = await _channel
          .invokeMethod<String>('sha256Recovery', bytes)
          .timeout(const Duration(seconds: 10));
      if (value == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
        throw const AssetFailure('Invalid recovery checksum result');
      }
      return value;
    } on MissingPluginException {
      throw const AssetFailure('Recovery requires the Windows candidate');
    } on PlatformException {
      throw const AssetFailure('Unable to verify recovery checksum');
    } on TimeoutException {
      throw const AssetFailure('Recovery checksum verification timed out');
    }
  }

  @override
  Future<bool> save(AssetImportV4Recovery recovery) async {
    final bytes = Uint8List.fromList(utf8.encode(recovery.json));
    if (bytes.length < 2 || bytes.length > AssetImportV4Recovery.maxBytes) {
      throw const AssetFailure('Invalid recovery file size');
    }
    try {
      // The operator-controlled modal dialog is not an automatic timed-out write.
      final value = await _channel.invokeMethod<Object?>(
        'saveRecoveryJson',
        bytes,
      );
      if (value == null) return false;
      if (value == true) return true;
      throw const AssetFailure('Invalid save result; inspect the destination');
    } on MissingPluginException {
      throw const AssetFailure('Recovery requires the Windows candidate');
    } on PlatformException catch (error) {
      throw AssetFailure(
        error.code == 'file_exists'
            ? 'File exists. Choose a new filename; nothing was overwritten.'
            : 'Unable to save recovery; inspect the destination.',
      );
    }
  }

  @override
  Future<Uint8List?> choose() async {
    try {
      final value = await _channel.invokeMethod<Object?>('chooseRecoveryJson');
      if (value == null) return null;
      if (value is! Uint8List ||
          value.length < 2 ||
          value.length > AssetImportV4Recovery.maxBytes) {
        throw const AssetFailure('Invalid or oversized recovery file');
      }
      return Uint8List.fromList(value);
    } on MissingPluginException {
      throw const AssetFailure('Recovery requires the Windows candidate');
    } on PlatformException {
      throw const AssetFailure('Unable to read a bounded recovery JSON file');
    }
  }
}

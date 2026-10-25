import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'api/asset_export.dart';
import 'api/asset_store.dart';

/// Export-only native boundary; the caller owns explicit user actions.
abstract interface class InventoryExportFiles {
  Future<String> digest(Uint8List bytes);
  Future<bool> save(AssetExport snapshot);
}

/// Windows CNG and native Save As; no paths, credentials or implicit disk writes.
class WindowsInventoryExportFiles implements InventoryExportFiles {
  static const _channel = MethodChannel('asset_desk/inventory_export');

  @override
  Future<String> digest(Uint8List bytes) async {
    if (bytes.length > 1024 * 1024) {
      throw const AssetFailure('Inventory payload exceeds 1 MiB');
    }
    try {
      final value = await _channel
          .invokeMethod<String>('sha256', bytes)
          .timeout(const Duration(seconds: 10));
      if (value == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
        throw const AssetFailure('Native checksum result is invalid');
      }
      return value;
    } on MissingPluginException {
      throw const AssetFailure(
        'Inventory export requires the Windows candidate',
      );
    } on PlatformException {
      throw const AssetFailure('Unable to verify inventory checksum');
    } on TimeoutException {
      throw const AssetFailure('Inventory checksum verification timed out');
    }
  }

  @override
  Future<bool> save(AssetExport snapshot) async {
    final bytes = Uint8List.fromList(utf8.encode(snapshot.json));
    if (bytes.length < 2 || bytes.length > 1024 * 1024) {
      throw const AssetFailure('Inventory export size is invalid');
    }
    try {
      // No timeout: a user-controlled modal dialog is not a timed-out write.
      final result = await _channel.invokeMethod<Object?>('saveJson', bytes);
      if (result == null) return false;
      if (result == true) return true;
      throw const AssetFailure(
        'Native save result is invalid; inspect the destination',
      );
    } on MissingPluginException {
      throw const AssetFailure('Saving JSON requires the Windows candidate');
    } on PlatformException catch (error) {
      throw AssetFailure(
        error.code == 'file_exists'
            ? 'File already exists. Choose a new filename; nothing was overwritten.'
            : 'Unable to save JSON; inspect the destination before trying again.',
      );
    }
  }
}

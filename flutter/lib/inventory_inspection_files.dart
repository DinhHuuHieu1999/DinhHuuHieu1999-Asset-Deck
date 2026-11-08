import 'package:flutter/services.dart';

import 'api/asset_store.dart';
import 'inventory_export_files.dart';

/// Explicit read-only file selection; null means the user cancelled.
abstract interface class InventoryInspectionFiles {
  Future<Uint8List?> choose();
  Future<String> digest(Uint8List bytes);
}

/// Native picker returns bounded bytes only, never a private filesystem path.
class WindowsInventoryInspectionFiles implements InventoryInspectionFiles {
  static const _channel = MethodChannel('asset_desk/inventory_export');
  final _exportFiles = WindowsInventoryExportFiles();

  @override
  Future<String> digest(Uint8List bytes) => _exportFiles.digest(bytes);

  @override
  Future<Uint8List?> choose() async {
    try {
      // No timeout for an operator-controlled modal dialog; never auto-retry.
      final result = await _channel.invokeMethod<Object?>(
        'chooseInspectionJson',
      );
      if (result == null) return null;
      if (result is! Uint8List ||
          result.length < 2 ||
          result.length > 1024 * 1024) {
        throw const AssetFailure(
          'Selected JSON exceeds bounds or has an invalid native result',
        );
      }
      return Uint8List.fromList(result);
    } on MissingPluginException {
      throw const AssetFailure(
        'Local JSON inspection requires the Windows candidate',
      );
    } on PlatformException {
      throw const AssetFailure('Unable to read a bounded local JSON file');
    }
  }
}

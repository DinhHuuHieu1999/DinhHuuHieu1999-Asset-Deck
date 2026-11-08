import 'asset.dart';

/// Explicit authenticated read of one asset, without scanning inventory pages.
abstract interface class AssetReadSource {
  Future<AssetRecord> readAsset(String id);
}

import 'asset.dart';

/// Expected request failure. A failed write may still have reached the server.
class AssetFailure implements Exception {
  const AssetFailure(
    this.message, {
    this.statusCode,
    this.definitelyNotSent = false,
  });
  final String message;
  final int? statusCode;
  final bool definitelyNotSent;
  @override
  String toString() => message;
}

/// Authenticated inventory boundary; production transport is implemented separately.
abstract interface class AssetStore {
  Future<AssetPage> list({
    required String query,
    required String status,
    required int offset,
  });
  Future<AssetRecord> create(AssetInput input);
  Future<AssetRecord> update(AssetRecord original, AssetInput input);
}

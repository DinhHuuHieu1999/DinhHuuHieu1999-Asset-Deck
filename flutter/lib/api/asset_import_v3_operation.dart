import 'asset_import_v3.dart';

/// One reviewed operation. Unknown outcomes lock the draft against replacement.
class AssetImportV3Operation {
  AssetImportV3Operation(this.draft, this.sessionRevision);

  /// A restored file never proves whether the original request was sent.
  AssetImportV3Operation.recovered(this.draft, this.sessionRevision)
    : _attempted = true;
  final AssetImportV3Draft draft;
  final int sessionRevision;
  bool _busy = false;
  bool _attempted = false;
  bool _invalidated = false;
  AssetImportV3Receipt? _receipt;
  bool get busy => _busy;
  bool get attempted => _attempted;
  bool get invalidated => _invalidated;
  AssetImportV3Receipt? get receipt => _receipt;

  /// Session changes permanently invalidate this review, including late replies.
  void invalidate() => _invalidated = true;

  /// A retry is always explicit and uses this same immutable draft/key.
  Future<void> confirm(
    AssetImportV3Source source, {
    required bool acknowledged,
    required String currentAccountId,
    required int currentSessionRevision,
  }) async {
    if (!acknowledged ||
        _busy ||
        _invalidated ||
        _receipt != null ||
        currentSessionRevision != sessionRevision) {
      throw StateError('Import confirmation is unavailable');
    }
    draft.requireAccount(currentAccountId);
    _busy = true;
    _attempted = true;
    try {
      final result = await source.importInventoryV3(
        draft,
        sessionRevision: sessionRevision,
      );
      if (_invalidated) throw StateError('Import session changed');
      // Revalidate even a custom implementation of the capability boundary.
      _receipt = AssetImportV3Receipt.parse({
        'requestId': result.requestId,
        'recordCount': result.recordIds.length,
        'recordIds': result.recordIds,
      }, draft);
    } finally {
      _busy = false;
    }
  }
}

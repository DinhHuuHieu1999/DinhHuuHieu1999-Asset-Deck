import 'asset_import.dart';

/// One reviewed operation. Unknown outcomes lock the draft against replacement.
class AssetImportOperation {
  AssetImportOperation(this.draft, this.sessionRevision);
  final AssetImportDraft draft;
  final int sessionRevision;
  bool _busy = false;
  bool _attempted = false;
  bool _invalidated = false;
  AssetImportReceipt? _receipt;
  bool get busy => _busy;
  bool get attempted => _attempted;
  bool get invalidated => _invalidated;
  AssetImportReceipt? get receipt => _receipt;

  /// Session changes permanently invalidate this review, including late replies.
  void invalidate() => _invalidated = true;

  /// A retry is always explicit and uses this same immutable draft/key.
  Future<void> confirm(
    AssetImportSource source, {
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
      final result = await source.importInventory(
        draft,
        sessionRevision: sessionRevision,
      );
      if (_invalidated) throw StateError('Import session changed');
      // Revalidate even a custom implementation of the capability boundary.
      _receipt = AssetImportReceipt.parse({
        'requestId': result.requestId,
        'recordCount': result.recordIds.length,
        'recordIds': result.recordIds,
      }, draft);
    } finally {
      _busy = false;
    }
  }
}

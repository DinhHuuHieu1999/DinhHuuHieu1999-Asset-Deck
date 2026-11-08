import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'api/asset_import.dart' show createAssetImportRequestId;
import 'api/asset_import_v2.dart';
import 'api/asset_import_v2_operation.dart';
import 'api/asset_inspection_v2.dart';
import 'api/asset_session.dart';
import 'inventory_inspection_files.dart';
import 'inventory_v2_recovery_files.dart';
import 'api/asset_import_v2_recovery.dart';

/// Explicit add-only write review, separate from read-only local inspection.
class InventoryImportV2Page extends StatefulWidget {
  const InventoryImportV2Page({
    super.key,
    required this.session,
    required this.source,
    required this.files,
    required this.apiBase,
    this.recoveryFiles,
  });
  final String apiBase;
  final InventoryV2RecoveryFiles? recoveryFiles;
  final AssetSession session;
  final AssetImportV2Source source;
  final InventoryInspectionFiles files;
  @override
  State<InventoryImportV2Page> createState() => _InventoryImportV2PageState();
}

class _InventoryImportV2PageState extends State<InventoryImportV2Page> {
  StreamSubscription<int>? _subscription;
  AssetImportV2Operation? _operation;
  bool _busy = false, _acknowledged = false;
  bool _recoverySaved = false;
  final _nativeRecovery = WindowsInventoryV2RecoveryFiles();
  InventoryV2RecoveryFiles get _recoveryFiles =>
      widget.recoveryFiles ?? _nativeRecovery;
  String? _message;
  bool _contextInvalidated = false;
  int _contextGeneration = 0;
  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _subscription = widget.session.sessionChanges.listen((_) {
      _contextInvalidated = true;
      _contextGeneration++;
      _operation?.invalidate();
      if (mounted)
        setState(() {
          _acknowledged = false;
          _message = 'Session changed. Close this review and sign in again.';
        });
    });
  }

  @override
  void didUpdateWidget(covariant InventoryImportV2Page oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session) ||
        !identical(oldWidget.source, widget.source) ||
        !identical(oldWidget.files, widget.files) ||
        !identical(oldWidget.recoveryFiles, widget.recoveryFiles) ||
        oldWidget.apiBase != widget.apiBase) {
      _operation?.invalidate();
      _contextInvalidated = true;
      _contextGeneration++;
      _acknowledged = false;
      _message = 'Import context changed. Close this review and start again.';
      unawaited(_subscription?.cancel());
      _listen();
    }
  }

  @override
  void dispose() {
    _operation?.invalidate();
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _choose() async {
    if (_busy || _contextInvalidated || (_operation?.attempted ?? false))
      return;
    final account = widget.session.account;
    final revision = widget.session.sessionRevision;
    final generation = _contextGeneration;
    if (account == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final bytes = await widget.files.choose();
      if (!mounted || generation != _contextGeneration) return;
      if (bytes == null) {
        setState(() => _message = 'Selection cancelled. Draft retained.');
        return;
      }
      setState(() {
        _operation = null;
        _recoverySaved = false;
        _acknowledged = false;
      });
      final snapshot = await inspectAssetV2Bytes(
        bytes,
        digest: widget.files.digest,
      );
      if (!mounted || generation != _contextGeneration) return;
      if (revision != widget.session.sessionRevision ||
          account.id != widget.session.account?.id)
        throw StateError('Session changed');
      final draft = AssetImportV2Draft.prepare(
        snapshot: snapshot,
        accountId: account.id,
        requestId: createAssetImportRequestId(),
      );
      setState(() {
        _operation = AssetImportV2Operation(draft, revision);
        _message = 'Checksum matches; authenticity is not verified. Nothing submitted.';
      });
    } catch (_) {
      if (mounted && generation == _contextGeneration)
        setState(() {
          _operation = null;
          _message = 'Unable to prepare import. Check file and session.';
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveRecovery() async {
    final operation = _operation;
    final generation = _contextGeneration;
    if (_busy ||
        _contextInvalidated ||
        operation == null ||
        operation.invalidated ||
        operation.receipt != null)
      return;
    setState(() {
      _busy = true;
      _acknowledged = false;
    });
    try {
      final recovery = await AssetImportV2Recovery.prepare(
        draft: operation.draft,
        apiBase: widget.apiBase,
        digest: _recoveryFiles.digest,
      );
      if (!mounted || generation != _contextGeneration) return;
      final saved = await _recoveryFiles.save(recovery);
      if (!mounted ||
          generation != _contextGeneration ||
          !identical(_operation, operation))
        return;
      setState(() {
        if (saved) _recoverySaved = true;
        _message = saved
            ? 'Private recovery file saved. Review and acknowledge before sending.'
            : 'Save cancelled. No new recovery file saved; draft retained.';
      });
    } catch (_) {
      if (mounted && generation == _contextGeneration) {
        setState(
          () => _message = 'Unable to save recovery. Submission requires a saved recovery file.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreRecovery() async {
    if (_busy || _contextInvalidated || (_operation?.attempted ?? false))
      return;
    final account = widget.session.account;
    final revision = widget.session.sessionRevision;
    final generation = _contextGeneration;
    if (account == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final bytes = await _recoveryFiles.choose();
      if (!mounted || generation != _contextGeneration) return;
      if (bytes == null) {
        setState(
          () => _message = 'Recovery selection cancelled. Draft retained.',
        );
        return;
      }
      setState(() {
        _operation = null;
        _recoverySaved = false;
        _acknowledged = false;
      });
      if (bytes.length > AssetImportV2Recovery.maxBytes) {
        throw const FormatException('Recovery file exceeds bounds');
      }
      final recovery = await AssetImportV2Recovery.parse(
        utf8.decode(bytes),
        currentApiBase: widget.apiBase,
        currentAccountId: account.id,
        digest: _recoveryFiles.digest,
      );
      if (!mounted || generation != _contextGeneration) return;
      if (revision != widget.session.sessionRevision ||
          account.id != widget.session.account?.id) {
        throw StateError('Session changed');
      }
      setState(() {
        _operation = AssetImportV2Operation.recovered(recovery.draft, revision);
        _recoverySaved = true;
        _message = 'Recovery validated; outcome unknown. Nothing submitted. Review before explicit same-key replay.';
      });
    } catch (_) {
      if (mounted && generation == _contextGeneration) {
        setState(
          () => _message = 'Unable to restore recovery. Check file, account and configured backend.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final operation = _operation;
    final account = widget.session.account;
    if (_busy ||
        _contextInvalidated ||
        operation == null ||
        account == null ||
        !_acknowledged ||
        !_recoverySaved)
      return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await operation.confirm(
        widget.source,
        acknowledged: _acknowledged,
        currentAccountId: account.id,
        currentSessionRevision: widget.session.sessionRevision,
      );
      if (mounted)
        setState(
          () => _message =
              'Import confirmed. Refresh inventory to see the new assets.',
        );
    } catch (_) {
      if (mounted && !operation.invalidated)
        setState(
          () => _message = 'Outcome not confirmed. Keep this review: retry only this same operation. Do not prepare a new import.',
        );
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
          _acknowledged = false;
        });
    }
  }

  Future<void> _requestLeave() async {
    if (_busy) return;
    final operation = _operation;
    final uncertain =
        operation != null &&
        operation.attempted &&
        operation.receipt == null &&
        !operation.invalidated;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          uncertain ? 'Keep this operation' : 'Discard import draft?',
        ),
        content: Text(
          uncertain
              ? 'The result is unknown. Keep this review or retain your private recovery file. Replay only the same operation; never create a new key blindly.'
              : 'Nothing has been submitted. Discard this local draft?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep review'),
          ),
          if (!uncertain)
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard draft'),
            ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => _operation = null);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final operation = _operation;
    final available =
        !_busy &&
        !_contextInvalidated &&
        operation != null &&
        !operation.invalidated &&
        operation.receipt == null;
    return PopScope(
      canPop:
          !_busy &&
          (operation == null ||
              operation.receipt != null ||
              operation.invalidated),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_requestLeave());
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Import inventory JSON v2')),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Add-only import. Existing assets are never replaced or deleted. Duplicate labels and serials are kept.',
                ),
                const Text(
                  'Review private serial numbers and notes before sending. This is separate from Inspect.',
                ),
                Text(
                  'Target account: ${widget.session.account?.name ?? 'Signed out'} (${widget.session.account?.id ?? '-'})',
                ),
                OutlinedButton(
                  onPressed:
                      _busy ||
                          _contextInvalidated ||
                          (operation?.attempted ?? false)
                      ? null
                      : _choose,
                  child: const Text('Choose import JSON (Windows)'),
                ),
                OutlinedButton(
                  onPressed:
                      _busy ||
                          _contextInvalidated ||
                          (operation?.attempted ?? false)
                      ? null
                      : _restoreRecovery,
                  child: const Text('Choose private recovery JSON (Windows)'),
                ),
                if (_busy)
                  const LinearProgressIndicator(
                    semanticsLabel: 'Processing inventory import',
                  ),
                if (_message != null)
                  Semantics(liveRegion: true, child: Text(_message!)),
                if (operation != null) ...[
                  Text(
                    'New assets: ${operation.draft.count}. Not your current inventory.',
                  ),
                  Text('Operation: ${operation.draft.requestId}'),
                  Text('Configured backend: ${widget.apiBase}'),
                  const Text(
                    'Recovery files contain plaintext private notes and serials. Save privately before submission. A checksum is not authenticity.',
                  ),
                  OutlinedButton(
                    onPressed: available ? _saveRecovery : null,
                    child: const Text('Save private recovery JSON (Windows)'),
                  ),
                  Text(
                    _recoverySaved
                        ? 'Recovery file available; retain it until the outcome is resolved.'
                        : 'Save recovery before confirming. Cancel or failure does not enable submission.',
                  ),
                  for (final record in operation.draft.records)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Name: ${record['name']}\nCategory: ${record['category']}\nSerial: ${record['serial']}\nStatus: ${record['status']}\nNotes: ${record['notes']}\nPurchased on: ${record['purchasedOn'] ?? 'Unknown'}\nWarranty expires on: ${record['warrantyExpiresOn'] ?? 'Unknown'}',
                        ),
                      ),
                    ),
                  CheckboxListTile(
                    value: _acknowledged,
                    onChanged: available && _recoverySaved
                        ? (value) =>
                              setState(() => _acknowledged = value ?? false)
                        : null,
                    title: const Text(
                      'I confirm the target account and these new records.',
                    ),
                  ),
                  FilledButton(
                    onPressed: available && _recoverySaved && _acknowledged
                        ? _confirm
                        : null,
                    child: Text(
                      operation.attempted
                          ? 'Replay same operation'
                          : 'Confirm new records',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

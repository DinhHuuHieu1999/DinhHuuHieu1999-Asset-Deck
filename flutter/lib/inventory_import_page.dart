import 'dart:async';

import 'package:flutter/material.dart';

import 'api/asset_import.dart';
import 'api/asset_import_operation.dart';
import 'api/asset_inspection.dart';
import 'api/asset_session.dart';
import 'inventory_inspection_files.dart';

/// Explicit add-only write review, separate from read-only local inspection.
class InventoryImportPage extends StatefulWidget {
  const InventoryImportPage({
    super.key,
    required this.session,
    required this.source,
    required this.files,
  });
  final AssetSession session;
  final AssetImportSource source;
  final InventoryInspectionFiles files;
  @override
  State<InventoryImportPage> createState() => _InventoryImportPageState();
}

class _InventoryImportPageState extends State<InventoryImportPage> {
  StreamSubscription<int>? _subscription;
  AssetImportOperation? _operation;
  bool _busy = false, _acknowledged = false;
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
  void didUpdateWidget(covariant InventoryImportPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session) ||
        !identical(oldWidget.source, widget.source) ||
        !identical(oldWidget.files, widget.files)) {
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
        _acknowledged = false;
      });
      final snapshot = await inspectAssetBytes(
        bytes,
        digest: widget.files.digest,
      );
      if (!mounted || generation != _contextGeneration) return;
      if (revision != widget.session.sessionRevision ||
          account.id != widget.session.account?.id)
        throw StateError('Session changed');
      final draft = AssetImportDraft.prepare(
        snapshot: snapshot,
        accountId: account.id,
        requestId: createAssetImportRequestId(),
      );
      setState(() {
        _operation = AssetImportOperation(draft, revision);
        _message = 'Checksum matches; authenticity is not verified. Nothing submitted.';
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _operation = null;
          _message = 'Unable to prepare import. Check file and session.';
        });
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
        !_acknowledged)
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
              ? 'The result is unknown. Closing loses the in-memory request key and risks duplicates. Keep this review and replay only the same operation.'
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
        appBar: AppBar(title: const Text('Import inventory JSON')),
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
                  for (final record in operation.draft.records)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Name: ${record['name']}\nCategory: ${record['category']}\nSerial: ${record['serial']}\nStatus: ${record['status']}\nNotes: ${record['notes']}',
                        ),
                      ),
                    ),
                  CheckboxListTile(
                    value: _acknowledged,
                    onChanged: available
                        ? (value) =>
                              setState(() => _acknowledged = value ?? false)
                        : null,
                    title: const Text(
                      'I confirm the target account and these new records.',
                    ),
                  ),
                  FilledButton(
                    onPressed: available && _acknowledged ? _confirm : null,
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

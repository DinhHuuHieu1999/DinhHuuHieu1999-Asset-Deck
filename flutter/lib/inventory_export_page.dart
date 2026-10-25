import 'package:flutter/material.dart';

import 'api/asset_export.dart';
import 'api/asset_store.dart';
import 'inventory_export_files.dart';

/// Explicit account-scoped export; the session owner replaces this route on change.
class InventoryExportPage extends StatefulWidget {
  const InventoryExportPage({
    super.key,
    required this.source,
    required this.files,
  });
  final AssetExportSource source;
  final InventoryExportFiles files;

  @override
  State<InventoryExportPage> createState() => _InventoryExportPageState();
}

class _InventoryExportPageState extends State<InventoryExportPage> {
  AssetExport? _snapshot;
  bool _busy = false;
  String? _message;

  Future<void> _prepare() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _snapshot = null;
      _message = null;
    });
    try {
      final result = await widget.source.exportInventory(
        digest: widget.files.digest,
      );
      if (mounted) setState(() => _snapshot = result);
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error is AssetFailure
              ? error.message
              : 'Unable to prepare inventory JSON. Nothing was saved.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final snapshot = _snapshot;
    if (_busy || snapshot == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final saved = await widget.files.save(snapshot);
      if (mounted) {
        setState(
          () => _message = saved
              ? 'Inventory JSON saved.'
              : 'Save cancelled. Prepared snapshot retained.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error is AssetFailure ? error.message : 'Unable to save JSON; inspect the destination before trying again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Export inventory JSON')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Export the full signed-in account inventory, not just the current '
              'search, status or page. Maximum 500 assets and 1 MiB; no partial export.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Sensitive plaintext: serial numbers and notes are included. '
              'Save privately. JSON v1 is not an encrypted database backup and '
              'does not provide import or restore.',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _prepare,
              child: const Text('Prepare JSON'),
            ),
            if (_busy)
              const LinearProgressIndicator(
                semanticsLabel: 'Export in progress',
              ),
            if (_snapshot case final snapshot?) ...[
              const SizedBox(height: 16),
              Text(
                'Complete snapshot: ${snapshot.count} ${snapshot.count == 1 ? 'asset' : 'assets'}',
              ),
              Text('Exported at: ${snapshot.exportedAt.toIso8601String()}'),
              const Text(
                'Checksum matches. This detects changes, not authenticity. '
                'Nothing is saved until you choose Save JSON as...',
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy ? null : _save,
                child: const Text('Save JSON as... (Windows)'),
              ),
            ],
            if (_message case final message?) ...[
              const SizedBox(height: 12),
              Semantics(liveRegion: true, child: Text(message)),
            ],
          ],
        ),
      ),
    ),
  );
}

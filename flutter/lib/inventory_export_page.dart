import 'package:flutter/material.dart';

import 'api/asset_export.dart';
import 'api/asset_export_v2.dart';
import 'api/asset_export_v3.dart';
import 'api/asset_store.dart';
import 'inventory_export_files.dart';

/// Explicit account-scoped export; the session owner replaces this route on change.
class InventoryExportPage extends StatefulWidget {
  const InventoryExportPage({
    super.key,
    required AssetExportSource source,
    required InventoryExportFiles files,
  }) : source = source,
       files = files,
       v2Source = null,
       v2Files = null,
       v3Source = null,
       v3Files = null;

  const InventoryExportPage.v2({
    super.key,
    required AssetExportV2Source source,
    required InventoryExportV2Files files,
  }) : v2Source = source,
       v2Files = files,
       source = null,
       files = null,
       v3Source = null,
       v3Files = null;

  const InventoryExportPage.v3({
    super.key,
    required AssetExportV3Source source,
    required InventoryExportV3Files files,
  }) : v3Source = source,
       v3Files = files,
       source = null,
       files = null,
       v2Source = null,
       v2Files = null;

  final AssetExportV3Source? v3Source;
  final InventoryExportV3Files? v3Files;
  final AssetExportSource? source;
  final InventoryExportFiles? files;
  final AssetExportV2Source? v2Source;
  final InventoryExportV2Files? v2Files;

  @override
  State<InventoryExportPage> createState() => _InventoryExportPageState();
}

class _PreparedExport {
  const _PreparedExport(this.count, this.exportedAt, this.save);
  final int count;
  final DateTime exportedAt;
  final Future<bool> Function() save;
}

class _InventoryExportPageState extends State<InventoryExportPage> {
  _PreparedExport? _snapshot;
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
      final _PreparedExport prepared;
      if (widget.v3Source case final source?) {
        final files = widget.v3Files!;
        final result = await source.exportInventoryV3(digest: files.digest);
        prepared = _PreparedExport(
          result.count,
          result.exportedAt,
          () => files.saveV3(result),
        );
      } else if (widget.v2Source case final source?) {
        final files = widget.v2Files!;
        final result = await source.exportInventoryV2(digest: files.digest);
        prepared = _PreparedExport(
          result.count,
          result.exportedAt,
          () => files.saveV2(result),
        );
      } else {
        final files = widget.files!;
        final result = await widget.source!.exportInventory(
          digest: files.digest,
        );
        prepared = _PreparedExport(
          result.count,
          result.exportedAt,
          () => files.save(result),
        );
      }
      if (mounted) setState(() => _snapshot = prepared);
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
      final saved = await snapshot.save();
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
    appBar: AppBar(
      title: Text(
        widget.v3Source != null
            ? 'Export inventory v3'
            : widget.v2Source == null
            ? 'Export inventory JSON'
            : 'Export inventory v2',
      ),
    ),
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
            Text(
              widget.v3Source != null
                  ? 'Sensitive plaintext includes serials, notes, dates and locations. Save privately; not an encrypted database backup.'
                  : widget.v2Source == null
                  ? 'Sensitive plaintext: serial numbers and notes are included. '
                        'Save privately. JSON v1 is not an encrypted database backup and '
                        'does not provide import or restore.'
                  : 'Sensitive plaintext: serial numbers, notes and dates are included. '
                        'Save privately. JSON v2 is not an encrypted database backup.',
            ),
            if (widget.v3Source != null) ...[
              const SizedBox(height: 12),
              const Text(
                'JSON v3 includes purchase/warranty dates and location. No v3 import or restore is available.',
              ),
            ],
            if (widget.v2Source != null) ...[
              const SizedBox(height: 12),
              const Text(
                'JSON v2 includes purchase and warranty dates. No v2 import or restore is available.',
              ),
            ],
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

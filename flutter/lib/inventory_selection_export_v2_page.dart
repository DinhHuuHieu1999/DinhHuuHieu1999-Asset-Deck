import 'package:flutter/material.dart';

import 'api/asset_selection_export_v2.dart';
import 'api/asset_store.dart';
import 'inventory_export_files.dart';

/// Explicit read-only selection export for an immutable applied filter identity.
class InventorySelectionExportV2Page extends StatefulWidget {
  const InventorySelectionExportV2Page({
    super.key,
    required this.source,
    required this.files,
    required this.scope,
  });
  final AssetSelectionExportV2Source source;
  final InventorySelectionExportV2Files files;
  final AssetSelectionScopeV2 scope;
  @override
  State<InventorySelectionExportV2Page> createState() =>
      _InventorySelectionExportV2PageState();
}

class _InventorySelectionExportV2PageState
    extends State<InventorySelectionExportV2Page> {
  AssetSelectionExportV2? _snapshot;
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
      final result = await widget.source.exportSelectionV2(
        scope: widget.scope,
        digest: widget.files.digest,
      );
      final expected = widget.scope.toQuery(), actual = result.scope.toQuery();
      if (expected.length != actual.length ||
          expected.entries.any((entry) => actual[entry.key] != entry.value)) {
        throw const AssetFailure('Selection filters do not match');
      }
      if (mounted) setState(() => _snapshot = result);
    } catch (error) {
      if (mounted)
        setState(
          () => _message = error is AssetFailure
              ? error.message
              : 'Unable to prepare matching selection',
        );
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
      final saved = await widget.files.saveSelectionV2(snapshot);
      if (mounted)
        setState(
          () => _message = saved
              ? 'Selection JSON saved.'
              : 'Save canceled. Prepared selection retained.',
        );
    } catch (error) {
      if (mounted)
        setState(
          () => _message = error is AssetFailure ? error.message : 'Unable to save JSON; inspect the destination before trying again.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Export matching assets v2')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'All matches, not just this page. Maximum 500 assets and 1 MiB; overflow stops export.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Selection only, not a full account backup. Sensitive plaintext includes serials, notes, dates, locations and manual check dates. Save privately.',
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              title: const Text('Applied filters'),
              initiallyExpanded: false,
              children: [
                for (final entry in widget.scope.toQuery().entries)
                  ListTile(
                    dense: true,
                    title: Text(entry.key),
                    subtitle: Text(
                      entry.value.isEmpty ? '(all / none)' : entry.value,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _prepare,
              child: const Text('Prepare selection JSON'),
            ),
            if (_busy)
              const LinearProgressIndicator(
                semanticsLabel: 'Selection export in progress',
              ),
            if (_snapshot case final snapshot?) ...[
              const SizedBox(height: 16),
              Text(
                'Matching selection: ${snapshot.count} ${snapshot.count == 1 ? 'asset' : 'assets'}',
              ),
              Text('Exported at: ${snapshot.exportedAt.toIso8601String()}'),
              const Text(
                'Checksum matches; not proof of authenticity. Use Save to write a private file.',
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy ? null : _save,
                child: const Text('Save selection JSON as... (Windows)'),
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

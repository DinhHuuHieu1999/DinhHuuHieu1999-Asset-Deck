import 'package:flutter/material.dart';

import 'api/asset_export.dart';
import 'api/asset_export_v3.dart';
import 'api/asset_inspection.dart';
import 'api/asset_selection_export.dart';
import 'inventory_inspection_files.dart';

/// Explicit local preview. No store, network client or import capability is held.
class InventoryInspectionPage extends StatefulWidget {
  const InventoryInspectionPage({
    super.key,
    required this.files,
    this.v3 = false,
  }) : selection = false;

  /// A distinct local selection inspector, never a full-export fallback.
  const InventoryInspectionPage.selection({super.key, required this.files})
    : v3 = false,
      selection = true;
  final InventoryInspectionFiles files;
  final bool v3;
  final bool selection;
  @override
  State<InventoryInspectionPage> createState() =>
      _InventoryInspectionPageState();
}

class _InventoryInspectionPageState extends State<InventoryInspectionPage> {
  AssetSelectionExport? _selectionPreview;
  AssetExport? _preview;
  AssetExportV3? _v3Preview;
  bool _busy = false;
  String? _message;

  Future<void> _choose() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final bytes = await widget.files.choose();
      if (!mounted) return;
      if (bytes == null) {
        setState(
          () => _message = 'Selection cancelled. Previous preview retained.',
        );
        return;
      }
      // A new selection invalidates old evidence before asynchronous verification.
      setState(() {
        _selectionPreview = null;
        _preview = null;
        _v3Preview = null;
      });
      if (widget.selection) {
        final preview = await inspectAssetSelectionBytes(
          bytes,
          digest: widget.files.digest,
        );
        if (!mounted) return;
        setState(() {
          _selectionPreview = preview;
          _message = 'Checksum matches';
        });
        return;
      }
      if (widget.v3) {
        final preview = await inspectAssetV3Bytes(
          bytes,
          digest: widget.files.digest,
        );
        if (!mounted) return;
        setState(() {
          _v3Preview = preview;
          _message = 'Checksum matches';
        });
        return;
      }
      final preview = await inspectAssetBytes(
        bytes,
        digest: widget.files.digest,
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _message = 'Checksum matches';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _selectionPreview = null;
        _preview = null;
        _v3Preview = null;
        _message =
            'Unable to inspect JSON. Check the format, size and checksum.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final v3Preview = _v3Preview;
    final selection = _selectionPreview;
    final count = selection?.count ?? v3Preview?.count ?? preview?.count ?? 0;
    final exportedAt =
        selection?.exportedAt ?? v3Preview?.exportedAt ?? preview?.exportedAt;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.selection
              ? 'Inspect selection JSON'
              : widget.v3
              ? 'Inspect inventory JSON v3'
              : 'Inspect inventory JSON',
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: 1 + count,
            itemBuilder: (context, index) {
              if (index == 0)
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Local file preview only. Nothing is imported or sent to the server.',
                    ),
                    Text(
                      widget.v3 || widget.selection
                          ? 'Files may contain sensitive serial numbers, notes, dates and locations. A matching checksum does not prove authenticity.'
                          : 'Files may contain sensitive serial numbers and notes. A matching checksum does not prove authenticity.',
                    ),
                    if (widget.selection)
                      const Text(
                        'Filtered selection only, not a full inventory backup. No import is available.',
                      ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _busy ? null : _choose,
                      child: const Text('Choose JSON file (Windows)'),
                    ),
                    if (_busy)
                      const LinearProgressIndicator(
                        semanticsLabel: 'Inspecting local JSON',
                      ),
                    if (selection != null &&
                        !_busy &&
                        _message != 'Checksum matches')
                      const Text('Checksum matches'),
                    if (_message != null)
                      Semantics(liveRegion: true, child: Text(_message!)),
                    if (exportedAt != null)
                      Text(
                        'Assets: $count; Exported: ${exportedAt.toIso8601String()}',
                      ),
                    if (selection != null)
                      ExpansionTile(
                        title: const Text('File filters'),
                        children: [
                          for (final entry in selection.scope.filters.entries)
                            ListTile(
                              title: Text(entry.key),
                              subtitle: Text('${entry.value ?? '(none)'}'),
                            ),
                        ],
                      ),
                    const SizedBox(height: 12),
                  ],
                );
              final v3Record =
                  selection?.records[index - 1] ??
                  v3Preview?.records[index - 1];
              final record = v3Record?.asset ?? preview!.records[index - 1];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.input.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (v3Record != null) ...[
                        Text('Location: ${v3Record.location ?? '(unknown)'}'),
                        Text(
                          'Purchased: ${v3Record.dates.purchasedOn ?? '(unknown)'}',
                        ),
                        Text(
                          'Warranty expires: ${v3Record.dates.warrantyExpiresOn ?? '(unknown)'}',
                        ),
                      ],
                      Text('Category: ${record.input.category}'),
                      Text('Status: ${record.input.status}'),
                      Text('Serial: ${record.input.serial}'),
                      Text('Notes: ${record.input.notes}'),
                      Text('ID: ${record.id}'),
                      Text('Version: ${record.version}'),
                      Text('Created: ${record.createdAt.toIso8601String()}'),
                      Text('Updated: ${record.updatedAt.toIso8601String()}'),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

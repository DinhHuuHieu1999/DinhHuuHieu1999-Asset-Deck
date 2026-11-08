import 'api/asset_export_v4.dart';
import 'api/asset_selection_export_v2.dart';

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
  }) : selection = false,
       selectionV2 = false,
       v4 = false;

  /// A distinct local selection inspector, never a full-export fallback.
  const InventoryInspectionPage.selection({super.key, required this.files})
    : v3 = false,
      selection = true,
      selectionV2 = false,
      v4 = false;

  /// Read-only v2 selection, never inferred from a full inventory file.
  const InventoryInspectionPage.selectionV2({super.key, required this.files})
    : v3 = false,
      selection = true,
      selectionV2 = true,
      v4 = false;

  /// Explicit full v4 parser, never a permissive version fallback.
  const InventoryInspectionPage.v4({super.key, required this.files})
    : v4 = true,
      v3 = false,
      selection = false,
      selectionV2 = false;
  final bool v4;
  final bool selectionV2;
  final InventoryInspectionFiles files;
  final bool v3;
  final bool selection;
  @override
  State<InventoryInspectionPage> createState() =>
      _InventoryInspectionPageState();
}

class _InventoryInspectionPageState extends State<InventoryInspectionPage> {
  AssetSelectionExport? _selectionPreview;
  AssetSelectionExportV2? _selectionV2Preview;
  AssetExport? _preview;
  AssetExportV3? _v3Preview;
  AssetExportV4? _v4Preview;
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
        _selectionV2Preview = null;
        _preview = null;
        _v3Preview = null;
        _v4Preview = null;
      });
      if (widget.v4) {
        final preview = await inspectAssetV4Bytes(
          bytes,
          digest: widget.files.digest,
        );
        if (!mounted) return;
        setState(() {
          _v4Preview = preview;
          _message = 'Checksum matches';
        });
        return;
      }
      if (widget.selectionV2) {
        final preview = await inspectAssetSelectionV2Bytes(
          bytes,
          digest: widget.files.digest,
        );
        if (!mounted) return;
        setState(() {
          _selectionV2Preview = preview;
          _message = 'Checksum matches';
        });
        return;
      }
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
        _selectionV2Preview = null;
        _preview = null;
        _v3Preview = null;
        _v4Preview = null;
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
    final v4Preview = _v4Preview;
    final selection = _selectionPreview;
    final selectionV2 = _selectionV2Preview;
    final count =
        v4Preview?.count ??
        selectionV2?.count ??
        selection?.count ??
        v3Preview?.count ??
        preview?.count ??
        0;
    final exportedAt =
        v4Preview?.exportedAt ??
        selectionV2?.exportedAt ??
        selection?.exportedAt ??
        v3Preview?.exportedAt ??
        preview?.exportedAt;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.v4
              ? 'Inspect inventory JSON v4'
              : widget.selectionV2
              ? 'Inspect selection JSON v2'
              : widget.selection
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
                      widget.v4 || widget.v3 || widget.selection
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
                    if ((v4Preview != null ||
                            selection != null ||
                            selectionV2 != null) &&
                        !_busy &&
                        _message != 'Checksum matches')
                      const Text('Checksum matches'),
                    if (_message != null)
                      Semantics(liveRegion: true, child: Text(_message!)),
                    if (exportedAt != null)
                      Text(
                        'Assets: $count; Exported: ${exportedAt.toIso8601String()}',
                      ),
                    if (selection != null || selectionV2 != null)
                      ExpansionTile(
                        title: const Text('File filters'),
                        children: [
                          for (final entry
                              in (selectionV2?.scope.toQuery() ??
                                      selection!.scope.filters)
                                  .entries)
                            ListTile(
                              title: Text(entry.key),
                              subtitle: Text('${entry.value ?? '(none)'}'),
                            ),
                        ],
                      ),
                    const SizedBox(height: 12),
                  ],
                );
              final v4Record = v4Preview?.records[index - 1];
              final v3Record =
                  selectionV2?.records[index - 1].record ??
                  selection?.records[index - 1] ??
                  v3Preview?.records[index - 1] ??
                  (v4Record == null
                      ? null
                      : AssetExportV3Record(
                          asset: v4Record.asset,
                          dates: v4Record.dates,
                          location: v4Record.location,
                        ));
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
                      if (v4Record != null)
                        Text(
                          'Last checked: ${v4Record.lastCheckedDate ?? '(unknown)'}',
                        ),
                      if (selectionV2 != null)
                        Text(
                          'Last checked: ${selectionV2.records[index - 1].lastCheckedDate ?? '(unknown)'}',
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

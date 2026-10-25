import 'package:flutter/material.dart';

import 'api/asset_export.dart';
import 'api/asset_inspection.dart';
import 'inventory_inspection_files.dart';

/// Explicit local preview. No store, network client or import capability is held.
class InventoryInspectionPage extends StatefulWidget {
  const InventoryInspectionPage({super.key, required this.files});
  final InventoryInspectionFiles files;
  @override
  State<InventoryInspectionPage> createState() =>
      _InventoryInspectionPageState();
}

class _InventoryInspectionPageState extends State<InventoryInspectionPage> {
  AssetExport? _preview;
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
      setState(() => _preview = null);
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
        _preview = null;
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
    return Scaffold(
      appBar: AppBar(title: const Text('Inspect inventory JSON')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: 1 + (preview?.count ?? 0),
            itemBuilder: (context, index) {
              if (index == 0)
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Local file preview only. Nothing is imported or sent to the server.',
                    ),
                    const Text(
                      'Files may contain sensitive serial numbers and notes. A matching checksum does not prove authenticity.',
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
                    if (_message != null)
                      Semantics(liveRegion: true, child: Text(_message!)),
                    if (preview != null)
                      Text(
                        'Assets: ${preview.count}; Exported: ${preview.exportedAt.toIso8601String()}',
                      ),
                    const SizedBox(height: 12),
                  ],
                );
              final record = preview!.records[index - 1];
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

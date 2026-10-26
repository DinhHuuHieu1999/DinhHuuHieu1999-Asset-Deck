import 'api/asset_session.dart';
import 'api/asset_import.dart';
import 'inventory_import_page.dart';

import 'package:flutter/material.dart';

import 'api/asset.dart';
import 'api/asset_store.dart';
import 'api/asset_export.dart';
import 'inventory_export_files.dart';
import 'inventory_export_page.dart';
import 'asset_editor.dart';
import 'inventory_inspection_files.dart';
import 'inventory_inspection_page.dart';

/// Inventory for one authenticated account; the parent must replace on sign-out.
class AssetsPage extends StatefulWidget {
  const AssetsPage({
    super.key,
    required this.store,
    this.exportFiles,
    this.inspectionFiles,
    this.enableInventoryImport = false,
    this.importApiBase = '',
  });
  final String importApiBase;
  final AssetStore store;
  final bool enableInventoryImport;
  final InventoryExportFiles? exportFiles;
  final InventoryInspectionFiles? inspectionFiles;
  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage> {
  final _query = TextEditingController();
  final _category = TextEditingController();
  String _loadedCategory = '';
  String _status = '', _loadedQuery = '', _loadedStatus = '';
  String? _error;
  AssetPage? _page;
  int _offset = 0;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _load({int offset = 0, bool apply = false}) async {
    if (_busy) return;
    final query = apply ? _query.text.trim() : _loadedQuery;
    final status = apply ? _status : _loadedStatus;
    final category = apply ? _category.text.trim() : _loadedCategory;
    if (_category.text.length > 64 || category.contains('\u0000')) {
      if (apply) {
        setState(
          () => _error = 'Category must be at most 64 characters without NUL.',
        );
        return;
      }
    }
    if (query.length > 120 || query.contains('\u0000')) {
      setState(
        () => _error = 'Search must be at most 120 characters without NUL.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.store.list(
        query: query,
        status: status,
        category: category,
        offset: offset,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _offset = offset;
        _loadedQuery = query;
        _loadedStatus = status;
        _loadedCategory = category;
      });
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error is AssetFailure
              ? error.message
              : 'Unable to load inventory.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([AssetRecord? record]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AssetEditor(store: widget.store, original: record),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Asset Desk')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Personal equipment inventory. Manual records only; nothing is run or installed.',
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _busy ? null : () => _edit(),
              child: const Text('Add asset'),
            ),
            if (widget.store case final AssetExportSource source) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => InventoryExportPage(
                            source: source,
                            files:
                                widget.exportFiles ??
                                WindowsInventoryExportFiles(),
                          ),
                        ),
                      ),
                child: const Text('Export all inventory JSON'),
              ),
            ],
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => InventoryInspectionPage(
                          files:
                              widget.inspectionFiles ??
                              WindowsInventoryInspectionFiles(),
                        ),
                      ),
                    ),
              child: const Text('Inspect local JSON (no import)'),
            ),
            if (widget.enableInventoryImport &&
                widget.store is AssetSession &&
                widget.store is AssetImportSource)
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => InventoryImportPage(
                            apiBase: widget.importApiBase,
                            session: widget.store as AssetSession,
                            source: widget.store as AssetImportSource,
                            files:
                                widget.inspectionFiles ??
                                WindowsInventoryInspectionFiles(),
                          ),
                        ),
                      ),
                child: const Text('Import inventory JSON (add only)'),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _query,
              maxLength: 120,
              enabled: !_busy,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Search assets',
                helperText: 'Name, category or serial; literal substring',
                helperMaxLines: 3,
              ),
              onSubmitted: (_) => _load(apply: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _category,
              enabled: !_busy,
              maxLength: 64,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Category filter',
                helperText: 'Exact, case-sensitive; blank means all categories',
                helperMaxLines: 3,
              ),
              onSubmitted: (_) => _load(apply: true),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              isExpanded: true,
              itemHeight: null,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Status filter',
              ),
              items: ['', ...assetStatuses]
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(s.isEmpty ? 'All statuses' : s),
                    ),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (s) => setState(() => _status = s ?? ''),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : () => _load(apply: true),
              child: const Text('Apply filters'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : () => _load(),
              child: const Text('Refresh inventory'),
            ),
            const Text(
              'Filters apply only when pressed. Refresh uses the last successfully applied filters.',
            ),
            if (_busy)
              const LinearProgressIndicator(
                semanticsLabel: 'Loading inventory',
              ),
            if (_error != null) Text(_error!, semanticsLabel: 'Error: $_error'),
            if (_error != null && _page != null)
              const Text(
                'The list below is from the last successful load; it may be stale.',
              ),
            if (_page != null) ...[
              Text(
                'Page ${_offset ~/ 50 + 1} - ${_page!.items.length} records',
              ),
              Text(
                'Applied search: ${_loadedQuery.isEmpty ? '(none)' : _loadedQuery}; status: ${_loadedStatus.isEmpty ? 'all' : _loadedStatus}; category: ${_loadedCategory.isEmpty ? 'all' : _loadedCategory}',
              ),
              if (_page!.items.isEmpty) const Text('No matching assets.'),
              for (final record in _page!.items)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.input.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${record.input.category} - ${record.input.status}',
                        ),
                        if (record.input.serial.isNotEmpty)
                          Text('Serial: ${record.input.serial}'),
                        if (record.input.notes.isNotEmpty)
                          Text(record.input.notes),
                        Text('Updated: ${record.updatedAt.toIso8601String()}'),
                        OutlinedButton(
                          onPressed: _busy ? null : () => _edit(record),
                          child: const Text('Edit asset'),
                        ),
                      ],
                    ),
                  ),
                ),
              Wrap(
                spacing: 12,
                children: [
                  if (_offset > 0)
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _load(offset: _offset - 50),
                      child: const Text('Previous page'),
                    ),
                  if (_page!.nextOffset != null)
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _load(offset: _page!.nextOffset!),
                      child: const Text('Next page'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

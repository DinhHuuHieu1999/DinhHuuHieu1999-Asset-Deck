import 'package:flutter/material.dart';

import 'api/asset_saved_filter.dart';

/// Account-scoped definitions; returning a selection never applies inventory.
class SavedFiltersPage extends StatefulWidget {
  const SavedFiltersPage({
    super.key,
    required this.source,
    required this.applied,
    required this.location,
    required this.warranty,
    required this.check,
    this.checkBefore = true,
    this.checkOnOrAfter = true,
  });
  final AssetSavedFilterSource source;
  final AssetSavedFilterQuery? applied;
  final bool location, warranty, check, checkBefore, checkOnOrAfter;
  @override
  State<SavedFiltersPage> createState() => _SavedFiltersPageState();
}

class _SavedFiltersPageState extends State<SavedFiltersPage> {
  List<AssetSavedFilter> _items = [];
  bool _busy = false;
  bool _needsReload = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted)
        setState(() {
          _needsReload = true;
          _error = 'Saved filters could not be updated. Reload before another write.';
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() => _run(() async {
    final items = await widget.source.listSavedFilters();
    if (mounted)
      setState(() {
        _items = items;
        _needsReload = false;
      });
  });
  String? _unsupported(AssetSavedFilterQuery query) {
    try {
      query.requireCapabilities(
        location: widget.location,
        warranty: widget.warranty,
        check: widget.check,
        checkBefore: widget.checkBefore,
        checkOnOrAfter: widget.checkOnOrAfter,
      );
      return null;
    } on FormatException {
      return 'Requires a capability not enabled in this client.';
    }
  }

  Future<String?> _name(String initial) async {
    final controller = TextEditingController(text: initial);
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Saved filter name'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 60,
            decoration: InputDecoration(labelText: 'Name', errorText: error),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  Navigator.pop(
                    context,
                    validateSavedFilterName(controller.text),
                  );
                } on FormatException {
                  update(() => error = 'Enter a name of 1-60 characters.');
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    // Disposal after dialog transition avoids a controller used during animation.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    return result;
  }

  Future<void> _save([AssetSavedFilter? original]) async {
    if (_busy || _needsReload) return;
    final query = original?.query ?? widget.applied;
    if (query == null || _unsupported(query) != null) return;
    final name = await _name(original?.name ?? '');
    if (!mounted || name == null) return;
    await _run(() async {
      if (original == null) {
        await widget.source.createSavedFilter(name, query);
      } else {
        await widget.source.updateSavedFilter(original, name, query);
      }
      final items = await widget.source.listSavedFilters();
      if (mounted)
        setState(() {
          _items = items;
          _needsReload = false;
        });
    });
  }

  Future<void> _delete(AssetSavedFilter item) async {
    if (_busy || _needsReload) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete saved filter?'),
        content: Text('Delete "${item.name}" only. Assets are not deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete saved filter'),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true) return;
    await _run(() async {
      await widget.source.deleteSavedFilter(item);
      final items = await widget.source.listSavedFilters();
      if (mounted)
        setState(() {
          _items = items;
          _needsReload = false;
        });
    });
  }

  String _summary(AssetSavedFilterQuery query) {
    final v = query.values;
    final parts = <String>[
      if (v['q']!.isNotEmpty) 'Search: ${v['q']}',
      if (v['status']!.isNotEmpty) 'Status: ${v['status']}',
      if (v['category']!.isNotEmpty) 'Category: ${v['category']}',
      'Sort: ${{'updated_desc': 'Recent updates', 'name_asc': 'Name A-Z', 'checked_asc': 'Oldest check date'}[v['sort']]}',
      if (v['locationMode'] == 'exact') 'Location: ${v['location']}',
      if (v['locationMode'] == 'unknown') 'Location: Unknown',
      if (v['warranty'] != 'all')
        'Warranty: ${v['warranty']} (fixed ${v['asOf']})',
      if (v['checkMode'] == 'unchecked') 'Check date: Unknown',
      if (v['checkMode'] == 'before') 'Checked before: ${v['checkBefore']}',
      if (v['checkMode'] == 'on_or_after')
        'Checked on/after: ${v['checkOnOrAfter']}',
    ];
    return parts.join('\n');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Saved filters')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Account-only query definitions, not asset backups. Selecting fills draft controls; press Apply in inventory. Fixed dates do not advance automatically.',
          ),
          OutlinedButton(
            onPressed: _busy ? null : _reload,
            child: const Text('Reload saved filters'),
          ),
          FilledButton(
            onPressed:
                _busy ||
                    _needsReload ||
                    widget.applied == null ||
                    _items.length >= 20
                ? null
                : () => _save(),
            child: const Text('Save applied filters'),
          ),
          if (widget.applied == null)
            const Text('Load inventory successfully before saving a query.'),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (!_busy && _items.isEmpty) const Text('No saved filters.'),
          for (final item in _items)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(_summary(item.query)),
                    if (_unsupported(item.query) case final String message)
                      Text(message),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          onPressed:
                              _busy ||
                                  _needsReload ||
                                  _unsupported(item.query) != null
                              ? null
                              : () => Navigator.pop(context, item.query),
                          child: const Text('Use as draft'),
                        ),
                        OutlinedButton(
                          onPressed:
                              _busy ||
                                  _needsReload ||
                                  _unsupported(item.query) != null
                              ? null
                              : () => _save(item),
                          child: const Text('Rename'),
                        ),
                        TextButton(
                          onPressed: _busy || _needsReload
                              ? null
                              : () => _delete(item),
                          child: const Text('Delete saved filter'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

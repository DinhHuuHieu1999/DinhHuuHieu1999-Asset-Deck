import 'api/asset_location_overview.dart';
import 'location_overview_page.dart';
import 'api/asset_import_v3.dart';
import 'inventory_import_v3_page.dart';
import 'api/asset_location.dart';
import 'asset_location_editor.dart';
import 'api/asset_import_v2.dart';
import 'inventory_import_v2_page.dart';
import 'api/asset_warranty_overview.dart';
import 'warranty_overview_page.dart';
import 'api/asset_warranty.dart';
import 'api/asset_dates.dart';
import 'asset_dates_editor.dart';
import 'api/asset_overview.dart';
import 'inventory_overview_page.dart';
import 'api/asset_session.dart';
import 'api/asset_import.dart';
import 'inventory_import_page.dart';

import 'package:flutter/material.dart';

import 'api/asset.dart';
import 'api/asset_store.dart';
import 'api/asset_export.dart';
import 'api/asset_export_v2.dart';
import 'api/asset_export_v3.dart';
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
    this.enableInventoryImportV2 = false,
    this.enableInventoryImportV3 = false,
    this.enableAssetDates = false,
    this.enableAssetLocation = false,
    this.enableInventoryExportV3 = false,
    this.importApiBase = '',
  });
  final String importApiBase;
  final AssetStore store;
  final bool enableInventoryImport;
  final bool enableInventoryImportV2;
  final bool enableInventoryImportV3;
  final bool enableAssetDates;
  final bool enableAssetLocation;
  final bool enableInventoryExportV3;
  final InventoryExportFiles? exportFiles;
  final InventoryInspectionFiles? inspectionFiles;
  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage> {
  final _query = TextEditingController();
  final _category = TextEditingController();
  final _location = TextEditingController();
  String _locationMode = 'all', _loadedLocationMode = 'all';
  String? _loadedLocation;
  String? _locationError;
  Map<String, String?> _locations = {};
  bool get _hasLocation =>
      widget.enableAssetLocation && widget.store is AssetLocationSource;
  String _loadedCategory = '';
  String _warranty = '', _loadedWarranty = '';
  AssetWarrantyPage? _warrantyPage;
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
    _location.dispose();
    super.dispose();
  }

  Future<void> _load({
    int offset = 0,
    bool apply = false,
    bool preserveWarrantyDate = false,
  }) async {
    if (_busy) return;
    final query = apply ? _query.text.trim() : _loadedQuery;
    final status = apply ? _status : _loadedStatus;
    final category = apply ? _category.text.trim() : _loadedCategory;
    final warranty = apply ? _warranty : _loadedWarranty;
    final locationMode = apply ? _locationMode : _loadedLocationMode;
    String? location = _loadedLocation;
    if (apply && _hasLocation) {
      try {
        location = locationMode == 'exact'
            ? normalizeAssetLocation(_location.text)
            : null;
      } on FormatException {
        setState(
          () => _locationError = 'Enter a location (1-120 characters), or select Unknown location.',
        );
        return;
      }
    }
    if (apply && _locationError != null) {
      setState(() => _locationError = null);
    }
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
      final AssetPage page;
      AssetWarrantyPage? warrantyPage;
      Map<String, String?> locations = {};
      if (_hasLocation) {
        final result = await (widget.store as AssetLocationSource)
            .listLocations(
              query: query,
              status: status,
              category: category,
              offset: offset,
              locationMode: locationMode,
              location: location,
              warranty: warranty,
              asOf: warranty.isNotEmpty && (offset > 0 || preserveWarrantyDate)
                  ? (_warrantyPage?.asOf ?? '')
                  : '',
            );
        page = AssetPage(
          result.items.map((entry) => entry.asset).toList(),
          result.nextOffset,
        );
        warrantyPage = result.warrantyPage;
        locations = {
          for (final entry in result.items) entry.asset.id: entry.location,
        };
      } else if (warranty.isNotEmpty) {
        if (!widget.enableAssetDates || widget.store is! AssetWarrantySource) {
          throw const AssetFailure('Warranty filtering is unavailable.');
        }
        warrantyPage = await (widget.store as AssetWarrantySource).listWarranty(
          query: query,
          status: status,
          category: category,
          warranty: warranty,
          offset: offset,
          asOf: offset > 0 || preserveWarrantyDate
              ? (_warrantyPage?.asOf ?? '')
              : '',
        );
        page = AssetPage(
          warrantyPage.items.map((item) => item.asset).toList(),
          warrantyPage.nextOffset,
        );
      } else {
        page = await widget.store.list(
          query: query,
          status: status,
          category: category,
          offset: offset,
        );
      }
      if (!mounted) return;
      setState(() {
        _page = page;
        _locations = locations;
        _loadedLocationMode = locationMode;
        _loadedLocation = location;
        _warrantyPage = warrantyPage;
        _loadedWarranty = warranty;
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

  Future<void> _editLocation(AssetRecord record) async {
    if (_busy || !_hasLocation) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    bool saved = false;
    try {
      final source = widget.store as AssetLocationSource;
      final original = await source.readLocation(record.id);
      if (!mounted) return;
      if (original.id.toLowerCase() != record.id.toLowerCase())
        throw const AssetFailure('Invalid asset location identity');
      saved =
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) =>
                  AssetLocationEditor(source: source, original: original),
            ),
          ) ==
          true;
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error is AssetFailure
              ? error.message
              : 'Unable to load asset location.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (saved && mounted) await _load();
  }

  Future<void> _editDates(AssetRecord record, AssetDatesSource source) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    bool saved = false;
    try {
      final dates = await source.readDates(record.id);
      if (!mounted) return;
      if (dates.id.toLowerCase() != record.id.toLowerCase()) {
        throw const AssetFailure('Invalid asset dates identity');
      }
      saved =
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => AssetDatesEditor(store: source, original: dates),
            ),
          ) ==
          true;
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error is AssetFailure
              ? error.message
              : 'Unable to load asset dates.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (saved && mounted) await _load();
  }

  Future<void> _edit([AssetRecord? record]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AssetEditor(store: widget.store, original: record),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _openLocationOverview() async {
    final selection = await Navigator.of(context)
        .push<LocationOverviewSelection>(
          MaterialPageRoute(
            builder: (_) => LocationOverviewPage(
              source: widget.store as AssetLocationOverviewSource,
            ),
          ),
        );
    if (!mounted || selection == null || _busy) return;
    setState(() {
      _query.clear();
      _category.clear();
      _status = '';
      _warranty = '';
      _locationMode = selection.location == null ? 'unknown' : 'exact';
      _location.text = selection.location ?? '';
      _locationError = null;
    });
    await _load(apply: true);
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
            if (_hasLocation &&
                widget.store is AssetLocationOverviewSource) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : _openLocationOverview,
                child: const Text('Location overview'),
              ),
            ],
            if (widget.enableAssetDates &&
                widget.store is AssetWarrantyOverviewSource) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => WarrantyOverviewPage(
                            source: widget.store as AssetWarrantyOverviewSource,
                          ),
                        ),
                      ),
                child: const Text('Warranty overview'),
              ),
            ],
            if (widget.store case final AssetOverviewSource source) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => InventoryOverviewPage(source: source),
                        ),
                      ),
                child: const Text('Inventory overview'),
              ),
            ],
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
            if (widget.enableAssetDates)
              if (widget.store case final AssetExportV2Source source) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => InventoryExportPage.v2(
                              source: source,
                              files:
                                  widget.exportFiles is InventoryExportV2Files
                                  ? widget.exportFiles!
                                        as InventoryExportV2Files
                                  : WindowsInventoryExportFiles(),
                            ),
                          ),
                        ),
                  child: const Text('Export JSON v2 with dates'),
                ),
              ],
            if (widget.enableInventoryExportV3 &&
                widget.enableAssetDates &&
                widget.enableAssetLocation)
              if (widget.store case final AssetExportV3Source source) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => InventoryExportPage.v3(
                              source: source,
                              files:
                                  widget.exportFiles is InventoryExportV3Files
                                  ? widget.exportFiles!
                                        as InventoryExportV3Files
                                  : WindowsInventoryExportFiles(),
                            ),
                          ),
                        ),
                  child: const Text('Export JSON v3 with dates and location'),
                ),
              ],
            if (widget.enableInventoryExportV3 &&
                widget.enableAssetDates &&
                widget.enableAssetLocation)
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => InventoryInspectionPage(
                            v3: true,
                            files:
                                widget.inspectionFiles ??
                                WindowsInventoryInspectionFiles(),
                          ),
                        ),
                      ),
                child: const Text('Inspect JSON v3 with location (no import)'),
              ),
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
            if (widget.enableInventoryImportV3 &&
                widget.enableInventoryImport &&
                widget.enableAssetDates &&
                widget.enableAssetLocation &&
                widget.store is AssetSession &&
                (widget.store as AssetSession).account != null &&
                widget.store is AssetImportV3Source)
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => InventoryImportV3Page(
                            apiBase: widget.importApiBase,
                            session: widget.store as AssetSession,
                            source: widget.store as AssetImportV3Source,
                            files:
                                widget.inspectionFiles ??
                                WindowsInventoryInspectionFiles(),
                          ),
                        ),
                      ),
                child: const Text(
                  'Import inventory JSON v3 (add-only, dates and location)',
                ),
              ),
            if (widget.enableInventoryImportV2 &&
                widget.enableInventoryImport &&
                widget.enableAssetDates &&
                widget.store is AssetSession &&
                (widget.store as AssetSession).account != null &&
                widget.store is AssetImportV2Source)
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => InventoryImportV2Page(
                            apiBase: widget.importApiBase,
                            session: widget.store as AssetSession,
                            source: widget.store as AssetImportV2Source,
                            files:
                                widget.inspectionFiles ??
                                WindowsInventoryInspectionFiles(),
                          ),
                        ),
                      ),
                child: const Text(
                  'Import inventory JSON v2 (add-only, with dates)',
                ),
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
            if (widget.enableAssetDates &&
                widget.store is AssetWarrantySource) ...[
              DropdownButtonFormField<String>(
                initialValue: _warranty,
                isExpanded: true,
                itemHeight: null,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Warranty filter (UTC)',
                  helperText: 'Unknown dates match only All warranties. Expiring includes today and the next 30 days.',
                  helperMaxLines: 5,
                ),
                selectedItemBuilder: (context) => const [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('All warranties'),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Expired'),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Due within 30d'),
                  ),
                ],
                items: const [
                  DropdownMenuItem(value: '', child: Text('All warranties')),
                  DropdownMenuItem(value: 'expired', child: Text('Expired')),
                  DropdownMenuItem(
                    value: 'expiring_soon',
                    child: Text('Expiring within 30 days'),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _warranty = value ?? ''),
              ),
              const SizedBox(height: 12),
            ],
            if (_hasLocation) ...[
              DropdownButtonFormField<String>(
                initialValue: _locationMode,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Location filter',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All locations')),
                  DropdownMenuItem(
                    value: 'unknown',
                    child: Text('Unknown location'),
                  ),
                  DropdownMenuItem(
                    value: 'exact',
                    child: Text('Exact location'),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _locationMode = value ?? 'all';
                        _locationError = null;
                      }),
              ),
              const SizedBox(height: 12),
              if (_locationMode == 'exact')
                TextField(
                  controller: _location,
                  enabled: !_busy,
                  maxLength: 120,
                  onChanged: (_) {
                    if (_locationError != null) {
                      setState(() => _locationError = null);
                    }
                  },
                  decoration: InputDecoration(
                    errorText: _locationError,
                    errorMaxLines: 4,
                    labelText: 'Exact location',
                    helperText: 'Case-sensitive; % and _ are literal.',
                    helperMaxLines: 3,
                    border: OutlineInputBorder(),
                  ),
                ),
              const SizedBox(height: 12),
            ],
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
              if (_hasLocation)
                Text(
                  'Applied location: ${_loadedLocationMode == 'all'
                      ? 'all'
                      : _loadedLocationMode == 'unknown'
                      ? 'unknown'
                      : _loadedLocation}',
                ),
              if (_warrantyPage case final page?)
                Text(
                  'Applied warranty: ${page.warranty == 'expired' ? 'Expired before' : 'Expiring from'} '
                  '${page.asOf} UTC${page.warranty == 'expired' ? '' : ' through ${page.through} inclusive'}. '
                  'Apply/Refresh updates the reference date.',
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
                        if (_warrantyPage case final page?)
                          Text(
                            'Warranty ends: ${page.items.firstWhere((item) => item.asset.id == record.id).dates.warrantyExpiresOn}',
                          ),
                        if (_hasLocation) ...[
                          Text(
                            'Location: ${_locations[record.id] ?? 'Unknown'}',
                          ),
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => _editLocation(record),
                            child: const Text('Edit location'),
                          ),
                        ],
                        Text('Updated: ${record.updatedAt.toIso8601String()}'),
                        OutlinedButton(
                          onPressed: _busy ? null : () => _edit(record),
                          child: const Text('Edit asset'),
                        ),
                        if (widget.enableAssetDates)
                          if (widget.store case final AssetDatesSource source)
                            OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => _editDates(record, source),
                              child: const Text('Purchase / warranty dates'),
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
                          : () => _load(
                              offset: _offset - 50,
                              preserveWarrantyDate: true,
                            ),
                      child: const Text('Previous page'),
                    ),
                  if (_page!.nextOffset != null)
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _load(
                              offset: _page!.nextOffset!,
                              preserveWarrantyDate: true,
                            ),
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

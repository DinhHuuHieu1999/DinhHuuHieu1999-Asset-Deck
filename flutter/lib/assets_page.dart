import 'api/asset_saved_filter.dart';
import 'saved_filters_page.dart';
import 'api/asset_export_v4.dart';
import 'api/asset_selection_export_v2.dart';
import 'inventory_selection_export_v2_page.dart';
import 'api/asset_check_overview.dart';
import 'check_overview_page.dart';
import 'api/asset_check.dart';
import 'asset_check_editor.dart';
import 'api/asset_read.dart';
import 'api/asset_selection_export.dart';
import 'inventory_selection_export_page.dart';
import 'api/asset_sort.dart';
import 'asset_details_page.dart';
import 'api/asset_location_overview.dart';
import 'location_overview_page.dart';
import 'api/asset_import_v4.dart';
import 'inventory_import_v4_page.dart';
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
    this.enableInventoryImportV4 = false,
    this.enableInventoryImportV3 = false,
    this.enableSavedFilters = false,
    this.enableAssetDates = false,
    this.enableAssetLocation = false,
    this.enableAssetCheck = false,
    this.enableInventoryExportV3 = false,
    this.enableInventoryExportV4 = false,
    this.enableSelectionExport = false,
    this.enableSelectionExportV2 = false,
    this.importApiBase = '',
  });
  final bool enableSavedFilters;
  final String importApiBase;
  final AssetStore store;
  final bool enableInventoryImport;
  final bool enableInventoryImportV2;
  final bool enableInventoryImportV4;
  final bool enableInventoryImportV3;
  final bool enableAssetDates;
  final bool enableAssetLocation;
  final bool enableAssetCheck;
  final bool enableInventoryExportV3;
  final bool enableInventoryExportV4;
  final bool enableSelectionExport;
  final bool enableSelectionExportV2;
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
  bool _unchecked = false, _loadedUnchecked = false;
  bool _beforeCheck = false;
  bool _onOrAfterCheck = false, _loadedOnOrAfterCheck = false;
  final _checkBefore = TextEditingController();
  String _loadedCheckBefore = '';
  String? _checkBeforeError;
  bool get _hasCheckBefore =>
      _hasCheck && widget.store is AssetCheckBeforeSource;
  bool get _hasCheck =>
      widget.enableAssetCheck && widget.store is AssetCheckSource;
  String _loadedCategory = '';
  String _warranty = '', _loadedWarranty = '';
  AssetWarrantyPage? _warrantyPage;
  String? _pinnedWarrantyAsOf;
  String? _savedWarrantyReference;
  String _status = '', _loadedQuery = '', _loadedStatus = '';
  String _sort = 'updated_desc', _loadedSort = 'updated_desc';
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
    _checkBefore.dispose();
    _query.dispose();
    _category.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _openSavedFilters() async {
    final store = widget.store;
    if (_busy || store is! AssetSavedFilterSource) return;
    final revision = store is AssetSession ? store.sessionRevision : null;
    AssetSavedFilterQuery? applied;
    if (_page != null) {
      applied = AssetSavedFilterQuery.fromJson({
        'q': _loadedQuery,
        'status': _loadedStatus,
        'category': _loadedCategory,
        'sort': _loadedSort,
        'locationMode': _loadedLocationMode,
        'location': _loadedLocationMode == 'exact'
            ? (_loadedLocation ?? '')
            : '',
        'warranty': _loadedWarranty.isEmpty ? 'all' : _loadedWarranty,
        'asOf': _loadedWarranty.isEmpty ? '' : (_warrantyPage?.asOf ?? ''),
        'checkMode': _loadedCheckBefore.isNotEmpty
            ? (_loadedOnOrAfterCheck ? 'on_or_after' : 'before')
            : (_loadedUnchecked ? 'unchecked' : 'all'),
        'checkBefore': _loadedOnOrAfterCheck ? '' : _loadedCheckBefore,
        'checkOnOrAfter': _loadedOnOrAfterCheck ? _loadedCheckBefore : '',
      });
    }
    final selected = await Navigator.of(context).push<AssetSavedFilterQuery>(
      MaterialPageRoute(
        builder: (_) => SavedFiltersPage(
          source: store as AssetSavedFilterSource,
          applied: applied,
          location: _hasLocation,
          warranty: widget.enableAssetDates && store is AssetWarrantySource,
          check: _hasCheck,
          checkBefore: _hasCheckBefore,
          checkOnOrAfter: _hasCheckBefore && store is AssetCheckOnOrAfterSource,
        ),
      ),
    );
    if (!mounted ||
        selected == null ||
        (store is AssetSession && store.sessionRevision != revision))
      return;
    final v = selected.values;
    setState(() {
      _query.text = v['q']!;
      _category.text = v['category']!;
      _status = v['status']!;
      _sort = v['sort']!;
      _locationMode = v['locationMode']!;
      _location.text = v['location']!;
      _warranty = v['warranty'] == 'all' ? '' : v['warranty']!;
      _savedWarrantyReference = v['asOf']!.isEmpty ? null : v['asOf'];
      _unchecked = v['checkMode'] == 'unchecked';
      _beforeCheck =
          v['checkMode'] == 'before' || v['checkMode'] == 'on_or_after';
      _onOrAfterCheck = v['checkMode'] == 'on_or_after';
      _checkBefore.text = _onOrAfterCheck
          ? v['checkOnOrAfter']!
          : v['checkBefore']!;
      _locationError = null;
      _checkBeforeError = null;
    });
  }

  Future<void> _openSelectionExport() async {
    if (_busy ||
        _page == null ||
        _error != null ||
        _loadedUnchecked ||
        _loadedSort == 'checked_asc' ||
        _loadedCheckBefore.isNotEmpty)
      return;
    final scope = AssetSelectionScope.fromJson({
      'q': _loadedQuery,
      'status': _loadedStatus,
      'category': _loadedCategory,
      'locationMode': _loadedLocationMode,
      'location': _loadedLocation,
      'sort': _loadedSort,
      'warranty': _loadedWarranty.isEmpty
          ? null
          : {
              'filter': _loadedWarranty,
              'asOf': _warrantyPage!.asOf,
              'through': _warrantyPage!.through,
            },
    });
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => InventorySelectionExportPage(
          source: widget.store as AssetSelectionExportSource,
          files: widget.exportFiles is InventorySelectionExportFiles
              ? widget.exportFiles! as InventorySelectionExportFiles
              : WindowsInventoryExportFiles(),
          scope: scope,
        ),
      ),
    );
  }

  Future<void> _openSelectionExportV2() async {
    if (_busy ||
        _page == null ||
        _error != null ||
        _loadedSort == 'checked_asc')
      return;
    final scope = AssetSelectionScopeV2.fromJson({
      'check': _loadedCheckBefore.isNotEmpty
          ? {
              'mode': _loadedOnOrAfterCheck ? 'on_or_after' : 'before',
              'cutoff': _loadedCheckBefore,
            }
          : {'mode': _loadedUnchecked ? 'unknown' : 'all'},
      'q': _loadedQuery,
      'status': _loadedStatus,
      'category': _loadedCategory,
      'locationMode': _loadedLocationMode,
      'location': _loadedLocation,
      'sort': _loadedSort,
      'warranty': _loadedWarranty.isEmpty
          ? null
          : {
              'filter': _loadedWarranty,
              'asOf': _warrantyPage!.asOf,
              'through': _warrantyPage!.through,
            },
    });
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => InventorySelectionExportV2Page(
          source: widget.store as AssetSelectionExportV2Source,
          files: widget.exportFiles is InventorySelectionExportV2Files
              ? widget.exportFiles! as InventorySelectionExportV2Files
              : WindowsInventoryExportFiles(),
          scope: scope,
        ),
      ),
    );
  }

  Future<void> _viewDetails(AssetRecord record) async {
    if (_busy) return;
    final store = widget.store;
    final revision = store is AssetSession ? store.sessionRevision : null;
    Future<bool> openEditor(Widget editor) async {
      if (!mounted ||
          (store is AssetSession && store.sessionRevision != revision)) {
        return false;
      }
      return await Navigator.of(context)
              .push<bool>(MaterialPageRoute(builder: (_) => editor)) ==
          true;
    }

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AssetDetailsPage(
          record: record,
          readSource: store is AssetReadSource
              ? store as AssetReadSource
              : null,
          onEdit: (original) =>
              openEditor(AssetEditor(store: store, original: original)),
          onDuplicate: (source) =>
              openEditor(AssetEditor.duplicate(store: store, source: source)),
          onEditDates: widget.enableAssetDates && store is AssetDatesSource
              ? (original) => openEditor(
                  AssetDatesEditor(
                    store: store as AssetDatesSource,
                    original: original,
                  ),
                )
              : null,
          onEditLocation: _hasLocation
              ? (original) => openEditor(
                  AssetLocationEditor(
                    source: store as AssetLocationSource,
                    original: original,
                  ),
                )
              : null,
          datesSource: widget.enableAssetDates && store is AssetDatesSource
              ? store as AssetDatesSource
              : null,
          locationSource: _hasLocation ? store as AssetLocationSource : null,
          checkSource: widget.enableAssetCheck && store is AssetCheckSource
              ? store as AssetCheckSource
              : null,
          onCheckToday: widget.enableAssetCheck && store is AssetCheckSource
              ? (original) => openEditor(
                  AssetCheckEditor(
                    source: store as AssetCheckSource,
                    original: original,
                    useToday: true,
                  ),
                )
              : null,
          onEditCheck: widget.enableAssetCheck && store is AssetCheckSource
              ? (original) => openEditor(
                  AssetCheckEditor(
                    source: store as AssetCheckSource,
                    original: original,
                  ),
                )
              : null,
          session: store is AssetSession ? store : null,
        ),
      ),
    );
    if (saved == true &&
        mounted &&
        (store is! AssetSession || store.sessionRevision == revision)) {
      await _load(offset: _offset, preserveWarrantyDate: true);
    }
  }

  Future<void> _load({
    int offset = 0,
    bool apply = false,
    bool resetFilters = false,
    bool preserveWarrantyDate = false,
    String? warrantyReference,
  }) async {
    if (_busy) return;
    final query = resetFilters
        ? ''
        : (apply ? _query.text.trim() : _loadedQuery);
    final status = resetFilters ? '' : (apply ? _status : _loadedStatus);
    final sort = apply && !resetFilters ? _sort : _loadedSort;
    final category = resetFilters
        ? ''
        : (apply ? _category.text.trim() : _loadedCategory);
    final unchecked =
        _hasCheck && !resetFilters && (apply ? _unchecked : _loadedUnchecked);
    final checkBefore = _hasCheckBefore && !resetFilters
        ? (apply ? (_beforeCheck ? _checkBefore.text : '') : _loadedCheckBefore)
        : '';
    final onOrAfterCheck =
        checkBefore.isNotEmpty &&
        !resetFilters &&
        (apply ? _onOrAfterCheck : _loadedOnOrAfterCheck);
    if (apply &&
        !resetFilters &&
        _hasCheckBefore &&
        _beforeCheck &&
        !isAssetCalendarDate(checkBefore)) {
      setState(() => _checkBeforeError = 'Enter a real date as YYYY-MM-DD.');
      return;
    }
    if (apply || resetFilters) _checkBeforeError = null;
    final warranty = resetFilters ? '' : (apply ? _warranty : _loadedWarranty);
    final reference =
        warrantyReference ??
        (apply && !resetFilters ? _savedWarrantyReference : null) ??
        (!apply && _pinnedWarrantyAsOf != null
            ? _pinnedWarrantyAsOf!
            : (offset > 0 || preserveWarrantyDate
                  ? (_warrantyPage?.asOf ?? '')
                  : ''));
    final locationMode = resetFilters
        ? 'all'
        : (apply ? _locationMode : _loadedLocationMode);
    String? location = resetFilters ? null : _loadedLocation;
    if (apply && !resetFilters && _hasLocation) {
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
    if (!resetFilters &&
        (_category.text.runes.length > 64 || category.contains('\u0000'))) {
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
      if (checkBefore.isNotEmpty) {
        final result = onOrAfterCheck
            ? await (widget.store as AssetCheckOnOrAfterSource)
                  .listCheckedOnOrAfter(
                    checkOnOrAfter: checkBefore,
                    query: query,
                    status: status,
                    offset: offset,
                    sort: sort,
                    category: category,
                    includeLocation: _hasLocation,
                    locationMode: locationMode,
                    location: location,
                    warranty: warranty,
                    asOf: reference,
                  )
            : await (widget.store as AssetCheckBeforeSource).listCheckedBefore(
                checkBefore: checkBefore,
                query: query,
                status: status,
                offset: offset,
                sort: sort,
                category: category,
                includeLocation: _hasLocation,
                locationMode: locationMode,
                location: location,
                warranty: warranty,
                asOf: reference,
              );
        page = result.page;
        warrantyPage = result.warranty;
        locations = result.locations;
      } else if (unchecked) {
        final result = await (widget.store as AssetCheckSource).listUnchecked(
          query: query,
          status: status,
          offset: offset,
          sort: sort,
          category: category,
          includeLocation: _hasLocation,
          locationMode: locationMode,
          location: location,
          warranty: warranty,
          asOf: warranty.isNotEmpty ? reference : '',
        );
        page = result.page;
        locations = result.locations;
        warrantyPage = result.warranty;
      } else if (_hasLocation) {
        final result = await (widget.store as AssetLocationSource)
            .listLocations(
              sort: sort,
              query: query,
              status: status,
              category: category,
              offset: offset,
              locationMode: locationMode,
              location: location,
              warranty: warranty,
              asOf: warranty.isNotEmpty ? reference : '',
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
          sort: sort,
          query: query,
          status: status,
          category: category,
          warranty: warranty,
          offset: offset,
          asOf: reference,
        );
        page = AssetPage(
          warrantyPage.items.map((item) => item.asset).toList(),
          warrantyPage.nextOffset,
        );
      } else {
        page = await widget.store.list(
          sort: sort,
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
        _pinnedWarrantyAsOf = warranty.isEmpty
            ? null
            : (apply
                  ? (warrantyReference ?? _savedWarrantyReference)
                  : _pinnedWarrantyAsOf);
        _offset = offset;
        _loadedQuery = query;
        _loadedStatus = status;
        _loadedSort = sort;
        _loadedCategory = category;
        _loadedUnchecked = unchecked;
        _loadedCheckBefore = checkBefore;
        _loadedOnOrAfterCheck = onOrAfterCheck;
        if (resetFilters) {
          _unchecked = false;
          _beforeCheck = false;
          _onOrAfterCheck = false;
          _checkBefore.clear();
          _checkBeforeError = null;
          _query.clear();
          _category.clear();
          _location.clear();
          _status = '';
          _warranty = '';
          _savedWarrantyReference = null;
          _locationMode = 'all';
          _locationError = null;
          _sort = sort;
        }
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

  Future<void> _openCheckOverview() async {
    final store = widget.store;
    final revision = store is AssetSession ? store.sessionRevision : null;
    final selection = await Navigator.of(context).push<CheckOverviewSelection>(
      MaterialPageRoute(
        builder: (_) =>
            CheckOverviewPage(source: store as AssetCheckOverviewSource),
      ),
    );
    if (!mounted ||
        selection == null ||
        _busy ||
        !identical(store, widget.store) ||
        (store is AssetSession && store.sessionRevision != revision))
      return;
    setState(() {
      _sort = _loadedSort;
      _unchecked = selection.mode == 'unchecked';
      _beforeCheck = !_unchecked;
      _onOrAfterCheck = selection.mode == 'on_or_after';
      _checkBefore.text = _unchecked ? '' : selection.cutoff;
      _checkBeforeError = null;
      _query.clear();
      _category.clear();
      _status = '';
      _warranty = '';
      _locationMode = 'all';
      _location.clear();
      _locationError = null;
    });
    await _load(apply: true);
  }

  Future<void> _openWarrantyOverview() async {
    final store = widget.store;
    final revision = store is AssetSession ? store.sessionRevision : null;
    final selection = await Navigator.of(context)
        .push<WarrantyOverviewSelection>(
          MaterialPageRoute(
            builder: (_) => WarrantyOverviewPage(
              source: store as AssetWarrantyOverviewSource,
            ),
          ),
        );
    if (!mounted ||
        selection == null ||
        _busy ||
        !identical(store, widget.store) ||
        (store is AssetSession && store.sessionRevision != revision))
      return;
    setState(() {
      _sort = _loadedSort;
      _unchecked = false;
      _beforeCheck = false;
      _onOrAfterCheck = false;
      _checkBefore.clear();
      _checkBeforeError = null;
      _query.clear();
      _category.clear();
      _status = '';
      _warranty = selection.warranty;
      _locationMode = 'all';
      _location.clear();
      _locationError = null;
    });
    await _load(apply: true, warrantyReference: selection.asOf);
  }

  Future<void> _openInventoryOverview() async {
    final store = widget.store;
    final revision = store is AssetSession ? store.sessionRevision : null;
    final selection = await Navigator.of(context)
        .push<InventoryOverviewSelection>(
          MaterialPageRoute(
            builder: (_) =>
                InventoryOverviewPage(source: store as AssetOverviewSource),
          ),
        );
    if (!mounted ||
        selection == null ||
        _busy ||
        !identical(store, widget.store) ||
        (store is AssetSession && store.sessionRevision != revision))
      return;
    setState(() {
      _sort = _loadedSort;
      _unchecked = false;
      _beforeCheck = false;
      _onOrAfterCheck = false;
      _checkBefore.clear();
      _checkBeforeError = null;
      _query.clear();
      _category.text = selection.category;
      _status = selection.status;
      _warranty = '';
      _locationMode = 'all';
      _location.clear();
      _locationError = null;
    });
    await _load(apply: true);
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
      _sort = _loadedSort;
      _unchecked = false;
      _beforeCheck = false;
      _onOrAfterCheck = false;
      _checkBefore.clear();
      _checkBeforeError = null;
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
            if (_hasCheckBefore &&
                widget.store is AssetCheckOverviewSource &&
                widget.store is AssetCheckOnOrAfterSource) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : _openCheckOverview,
                child: const Text('Check-date overview'),
              ),
            ],
            if (widget.enableAssetDates &&
                widget.store is AssetWarrantyOverviewSource) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : _openWarrantyOverview,
                child: const Text('Warranty overview'),
              ),
            ],
            if (widget.store is AssetOverviewSource) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : _openInventoryOverview,
                child: const Text('Inventory overview'),
              ),
            ],
            if (widget.enableSelectionExport &&
                widget.enableAssetDates &&
                widget.enableAssetLocation &&
                widget.store is AssetSelectionExportSource) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed:
                    _busy ||
                        _page == null ||
                        _error != null ||
                        _loadedUnchecked ||
                        _loadedSort == 'checked_asc' ||
                        _loadedCheckBefore.isNotEmpty
                    ? null
                    : _openSelectionExport,
                child: const Text('Export matching assets JSON'),
              ),
              if (_loadedUnchecked || _loadedCheckBefore.isNotEmpty)
                const Text(
                  'Matching export is unavailable for check-date filters. Reset filters first.',
                ),
            ],
            if (_loadedSort == 'checked_asc' && widget.enableSelectionExport)
              const Text(
                'Matching JSON export does not support this sort. Apply Recent updates or Name A-Z to export.',
              ),
            if (widget.enableSelectionExportV2 &&
                widget.enableSelectionExport &&
                _hasCheck &&
                _hasLocation &&
                widget.enableAssetDates &&
                widget.store is AssetSelectionExportV2Source) ...[
              OutlinedButton(
                onPressed:
                    _busy ||
                        _page == null ||
                        _error != null ||
                        _loadedSort == 'checked_asc'
                    ? null
                    : _openSelectionExportV2,
                child: const Text(
                  'Export matching assets JSON v2 with check dates',
                ),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => InventoryInspectionPage.selectionV2(
                            files:
                                widget.inspectionFiles ??
                                WindowsInventoryInspectionFiles(),
                          ),
                        ),
                      ),
                child: const Text('Inspect selection JSON v2 (no import)'),
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
            if (widget.enableInventoryExportV4 &&
                widget.enableAssetDates &&
                widget.enableAssetLocation &&
                widget.enableAssetCheck)
              if (widget.store case final AssetExportV4Source source) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => InventoryExportPage.v4(
                              source: source,
                              files:
                                  widget.exportFiles is InventoryExportV4Files
                                  ? widget.exportFiles!
                                        as InventoryExportV4Files
                                  : WindowsInventoryExportFiles(),
                            ),
                          ),
                        ),
                  child: const Text('Export JSON v4 with manual check dates'),
                ),
              ],
            if (widget.enableInventoryExportV4 &&
                widget.enableAssetDates &&
                widget.enableAssetLocation &&
                widget.enableAssetCheck)
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => InventoryInspectionPage.v4(
                            files:
                                widget.inspectionFiles ??
                                WindowsInventoryInspectionFiles(),
                          ),
                        ),
                      ),
                child: const Text(
                  'Inspect JSON v4 with check dates (no import)',
                ),
              ),
            if (widget.enableSelectionExport &&
                widget.enableAssetDates &&
                widget.enableAssetLocation)
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => InventoryInspectionPage.selection(
                            files:
                                widget.inspectionFiles ??
                                WindowsInventoryInspectionFiles(),
                          ),
                        ),
                      ),
                child: const Text('Inspect selection JSON (no import)'),
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
            if (widget.enableInventoryImportV4 &&
                widget.enableInventoryImport &&
                widget.enableAssetDates &&
                widget.enableAssetLocation &&
                widget.enableAssetCheck &&
                widget.store is AssetSession &&
                (widget.store as AssetSession).account != null &&
                widget.store is AssetImportV4Source)
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => InventoryImportV4Page(
                            apiBase: widget.importApiBase,
                            session: widget.store as AssetSession,
                            source: widget.store as AssetImportV4Source,
                            files:
                                widget.inspectionFiles ??
                                WindowsInventoryInspectionFiles(),
                          ),
                        ),
                      ),
                child: const Text(
                  'Import inventory JSON v4 (add-only, with check dates)',
                ),
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
              key: ValueKey('saved-draft-_status-${_status}'),
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
            if (_hasCheck) ...[
              CheckboxListTile(
                title: const Text('Only unknown check dates'),
                subtitle: const Text(
                  'Unknown check date only. Apply filters to update results.',
                ),
                value: _unchecked,
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _unchecked = value ?? false;
                        if (_unchecked) {
                          _beforeCheck = false;
                          _onOrAfterCheck = false;
                        }
                        _checkBeforeError = null;
                      }),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              if (_hasCheckBefore) ...[
                CheckboxListTile(
                  title: Text(
                    _onOrAfterCheck ? 'Checked on or after' : 'Checked before',
                  ),
                  subtitle: Text(
                    _onOrAfterCheck
                        ? 'Includes the selected day; excludes Unknown dates.'
                        : 'Excludes the selected day and Unknown dates.',
                  ),
                  value: _beforeCheck,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _beforeCheck = value ?? false;
                          if (!_beforeCheck) _onOrAfterCheck = false;
                          if (_beforeCheck) _unchecked = false;
                          _checkBeforeError = null;
                        }),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                if (_beforeCheck) ...[
                  TextField(
                    controller: _checkBefore,
                    enabled: !_busy,
                    maxLength: 10,
                    decoration: InputDecoration(
                      labelText: _onOrAfterCheck
                          ? 'On or after date'
                          : 'Before date',
                    ),
                  ),
                  Text(
                    _onOrAfterCheck
                        ? 'YYYY-MM-DD; matching dates include the selected day.'
                        : 'YYYY-MM-DD; only earlier manual check dates match.',
                  ),
                ],
                if (_checkBeforeError != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _checkBeforeError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
              Text(
                'Applied check filter: ${_loadedCheckBefore.isNotEmpty
                    ? (_loadedOnOrAfterCheck ? "On or after $_loadedCheckBefore" : "Before $_loadedCheckBefore")
                    : _loadedUnchecked
                    ? "Unknown date"
                    : "All assets"}',
              ),
              const Text('Existing JSON exports exclude check dates.'),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<String>(
              key: ValueKey('inventory-sort-$_sort'),
              selectedItemBuilder: (context) => [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Recent updates'),
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Name A-Z'),
                ),
                if (_hasCheck)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Oldest checked'),
                  ),
              ],
              initialValue: _sort,
              isExpanded: true,
              itemHeight: null,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Sort inventory',
              ),
              items: [
                const DropdownMenuItem(
                  value: 'updated_desc',
                  child: Text('Updated most recently'),
                ),
                const DropdownMenuItem(
                  value: 'name_asc',
                  child: Text('Name A-Z'),
                ),
                if (_hasCheck)
                  const DropdownMenuItem(
                    value: 'checked_asc',
                    child: Text('Oldest check date (Unknown last)'),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value != null &&
                          assetListSorts.contains(value) &&
                          (value != 'checked_asc' || _hasCheck)) {
                        setState(() => _sort = value);
                      }
                    },
            ),
            const SizedBox(height: 12),
            if (widget.enableAssetDates &&
                widget.store is AssetWarrantySource) ...[
              DropdownButtonFormField<String>(
                key: ValueKey('saved-draft-_warranty-${_warranty}'),
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
                    : (value) => setState(() {
                        _warranty = value ?? '';
                        _savedWarrantyReference = null;
                      }),
              ),
              const SizedBox(height: 12),
            ],
            if (_hasLocation) ...[
              DropdownButtonFormField<String>(
                key: ValueKey('saved-draft-_locationMode-${_locationMode}'),
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
            if (widget.enableSavedFilters &&
                widget.store is AssetSavedFilterSource)
              OutlinedButton(
                onPressed: _busy ? null : _openSavedFilters,
                child: const Text('Saved filters'),
              ),
            if (_savedWarrantyReference != null)
              Text('Draft fixed warranty reference: $_savedWarrantyReference'),
            FilledButton(
              onPressed: _busy ? null : () => _load(apply: true),
              child: const Text('Apply filters'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : () => _load(),
              child: const Text('Refresh inventory'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : () => _load(resetFilters: true),
              child: const Text('Reset filters'),
            ),
            const Text(
              'Reset clears filters, keeps applied sort and loads page 1.',
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
              Text(
                'Applied sort: ${_loadedSort == 'checked_asc'
                    ? 'Oldest check date (Unknown last)'
                    : _loadedSort == 'name_asc'
                    ? 'Name A-Z'
                    : 'Updated most recently'}',
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
                          onPressed: _busy ? null : () => _viewDetails(record),
                          child: const Text('View details'),
                        ),
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

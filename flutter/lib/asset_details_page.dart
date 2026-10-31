import 'dart:async';

import 'package:flutter/material.dart';

import 'api/asset.dart';
import 'api/asset_read.dart';
import 'api/asset_dates.dart';
import 'api/asset_details.dart';
import 'api/asset_location.dart';
import 'api/asset_session.dart';

/// Selected list snapshot with verified optional information and explicit editing.
class AssetDetailsPage extends StatefulWidget {
  const AssetDetailsPage({
    super.key,
    required this.record,
    this.readSource,
    this.datesSource,
    this.locationSource,
    this.session,
    this.onEdit,
    this.onEditDates,
    this.onEditLocation,
  });
  final AssetRecord record;
  final AssetReadSource? readSource;
  final AssetDatesSource? datesSource;
  final AssetLocationSource? locationSource;
  final AssetSession? session;

  /// Opens editing for this exact snapshot; true means a confirmed save.
  final Future<bool> Function(AssetRecord record)? onEdit;

  /// Edits only the dates already verified against this snapshot's version.
  final Future<bool> Function(AssetDates dates)? onEditDates;

  /// Edits only the location already verified against this snapshot's version.
  final Future<bool> Function(AssetLocation location)? onEditLocation;

  @override
  State<AssetDetailsPage> createState() => _AssetDetailsPageState();
}

class _AssetDetailsPageState extends State<AssetDetailsPage> {
  late AssetRecord _record;
  AssetDetailsSnapshot? _details;
  StreamSubscription<int>? _subscription;
  int _request = 0;
  bool _invalidated = false;
  bool _busy = true;
  bool _editing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _record = widget.record;
    _bind();
    _load();
  }

  void _bind() {
    _subscription = widget.session?.sessionChanges.listen((_) {
      if (!mounted) return;
      _request++;
      setState(() {
        _details = null;
        _busy = false;
        _invalidated = true;
        _error = null;
      });
    });
  }

  @override
  void didUpdateWidget(covariant AssetDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.record, widget.record) ||
        !identical(oldWidget.readSource, widget.readSource) ||
        !identical(oldWidget.datesSource, widget.datesSource) ||
        !identical(oldWidget.locationSource, widget.locationSource) ||
        !identical(oldWidget.session, widget.session)) {
      _subscription?.cancel();
      _record = widget.record;
      _request++;
      _details = null;
      _error = null;
      _invalidated = false;
      _bind();
      _load();
    }
  }

  Future<void> _load({bool refresh = false}) async {
    final request = ++_request;
    final revision = widget.session?.sessionRevision;
    bool current() =>
        mounted &&
        request == _request &&
        !_invalidated &&
        widget.session?.sessionRevision == revision;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final record = refresh
          ? await widget.readSource!.readAsset(_record.id)
          : _record;
      if (!current()) return;
      if (record.id.toLowerCase() != _record.id.toLowerCase()) {
        throw StateError('Asset identity mismatch');
      }
      final value = await AssetDetailsSnapshot.load(
        record,
        datesSource: widget.datesSource,
        locationSource: widget.locationSource,
        isCurrent: current,
      );
      if (current())
        setState(() {
          _record = record;
          _details = value;
        });
    } catch (_) {
      if (current()) {
        setState(() {
          if (!refresh) _details = null;
          _error = refresh
              ? 'Refresh failed. Previous snapshot retained; it may be out of date. Editing is disabled until refresh succeeds.'
              : 'Could not verify dates and location for this snapshot. Return to inventory, refresh and reopen details.';
        });
      }
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  Future<void> _edit<T>(T? original, Future<bool> Function(T)? edit) async {
    if (original == null ||
        edit == null ||
        _busy ||
        _editing ||
        _invalidated ||
        _details == null ||
        _error != null)
      return;
    final request = _request;
    final revision = widget.session?.sessionRevision;
    setState(() => _editing = true);
    try {
      final saved = await edit(original);
      if (!mounted ||
          _invalidated ||
          request != _request ||
          revision != widget.session?.sessionRevision)
        return;
      if (saved) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted && !_invalidated && request == _request) {
        setState(
          () => _error =
              'Unable to open editing. Return to inventory and refresh.',
        );
      }
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  @override
  void dispose() {
    _request++;
    _subscription?.cancel();
    super.dispose();
  }

  Widget _field(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        SelectableText(value),
      ],
    ),
  );

  String get _unloaded => _busy ? 'Loading...' : 'Not verified';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Asset details')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_invalidated)
              const Text(
                'Session changed. Return to inventory and sign in again.',
              )
            else ...[
              Text(
                widget.readSource != null
                    ? 'Inventory snapshot, not a live record. Refresh details reads a new snapshot; editing uses the displayed version.'
                    : widget.onEdit == null &&
                          widget.onEditDates == null &&
                          widget.onEditLocation == null
                    ? 'Read-only inventory snapshot, not a live record. To update it, return to inventory, refresh and reopen.'
                    : 'Inventory snapshot, not a live record. Edit uses this version; a successful save returns to inventory.',
              ),
              if (widget.readSource != null)
                OutlinedButton(
                  onPressed: _busy || _editing
                      ? null
                      : () => _load(refresh: true),
                  child: const Text('Refresh details'),
                ),
              if (widget.onEdit != null)
                OutlinedButton(
                  onPressed:
                      _busy || _editing || _details == null || _error != null
                      ? null
                      : () => _edit(_record, widget.onEdit),
                  child: const Text('Edit asset'),
                ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              _field('Name', _record.input.name),
              _field('Category', _record.input.category),
              _field('Status', _record.input.status),
              _field(
                'Serial',
                _record.input.serial.isEmpty
                    ? 'Not provided'
                    : _record.input.serial,
              ),
              _field(
                'Notes',
                _record.input.notes.isEmpty
                    ? 'Not provided'
                    : _record.input.notes,
              ),
              _field(
                'Purchase date',
                widget.datesSource == null
                    ? 'Not enabled'
                    : _details?.dates != null
                    ? _details!.dates!.input.purchasedOn ?? 'Unknown'
                    : _unloaded,
              ),
              _field(
                'Warranty expiry',
                widget.datesSource == null
                    ? 'Not enabled'
                    : _details?.dates != null
                    ? _details!.dates!.input.warrantyExpiresOn ?? 'Unknown'
                    : _unloaded,
              ),
              if (widget.datesSource != null && widget.onEditDates != null)
                OutlinedButton(
                  onPressed:
                      _busy ||
                          _editing ||
                          _error != null ||
                          _details?.dates == null
                      ? null
                      : () => _edit(_details?.dates, widget.onEditDates),
                  child: const Text('Edit purchase / warranty dates'),
                ),
              _field(
                'Location',
                widget.locationSource == null
                    ? 'Not enabled'
                    : _details?.location != null
                    ? _details!.location!.location ?? 'Unknown'
                    : _unloaded,
              ),
              if (widget.locationSource != null &&
                  widget.onEditLocation != null)
                OutlinedButton(
                  onPressed:
                      _busy ||
                          _editing ||
                          _error != null ||
                          _details?.location == null
                      ? null
                      : () => _edit(_details?.location, widget.onEditLocation),
                  child: const Text('Edit location'),
                ),
              _field('Snapshot version', '${_record.version}'),
              _field(
                'Created (UTC)',
                _record.createdAt.toUtc().toIso8601String(),
              ),
              _field(
                'Updated (UTC)',
                _record.updatedAt.toUtc().toIso8601String(),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

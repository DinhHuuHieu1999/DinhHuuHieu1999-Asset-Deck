import 'dart:async';

import 'package:flutter/material.dart';

import 'api/asset.dart';
import 'api/asset_dates.dart';
import 'api/asset_details.dart';
import 'api/asset_location.dart';
import 'api/asset_session.dart';

/// Read-only selected list snapshot with version-verified optional information.
class AssetDetailsPage extends StatefulWidget {
  const AssetDetailsPage({
    super.key,
    required this.record,
    this.datesSource,
    this.locationSource,
    this.session,
  });
  final AssetRecord record;
  final AssetDatesSource? datesSource;
  final AssetLocationSource? locationSource;
  final AssetSession? session;

  @override
  State<AssetDetailsPage> createState() => _AssetDetailsPageState();
}

class _AssetDetailsPageState extends State<AssetDetailsPage> {
  AssetDetailsSnapshot? _details;
  StreamSubscription<int>? _subscription;
  int _request = 0;
  bool _invalidated = false;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
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
        !identical(oldWidget.datesSource, widget.datesSource) ||
        !identical(oldWidget.locationSource, widget.locationSource) ||
        !identical(oldWidget.session, widget.session)) {
      _subscription?.cancel();
      _request++;
      _details = null;
      _error = null;
      _invalidated = false;
      _bind();
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    final revision = widget.session?.sessionRevision;
    bool current() =>
        mounted &&
        request == _request &&
        !_invalidated &&
        widget.session?.sessionRevision == revision;
    setState(() => _busy = true);
    try {
      final value = await AssetDetailsSnapshot.load(
        widget.record,
        datesSource: widget.datesSource,
        locationSource: widget.locationSource,
        isCurrent: current,
      );
      if (current()) setState(() => _details = value);
    } catch (_) {
      if (current()) {
        setState(() {
          _details = null;
          _error =
              'Could not verify dates and location for this snapshot. '
              'Return to inventory, refresh and reopen details.';
        });
      }
    } finally {
      if (current()) setState(() => _busy = false);
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
              const Text(
                'Read-only inventory snapshot, not a live record. '
                'To update it, return to inventory, refresh and reopen.',
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
              _field('Name', widget.record.input.name),
              _field('Category', widget.record.input.category),
              _field('Status', widget.record.input.status),
              _field(
                'Serial',
                widget.record.input.serial.isEmpty
                    ? 'Not provided'
                    : widget.record.input.serial,
              ),
              _field(
                'Notes',
                widget.record.input.notes.isEmpty
                    ? 'Not provided'
                    : widget.record.input.notes,
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
              _field(
                'Location',
                widget.locationSource == null
                    ? 'Not enabled'
                    : _details?.location != null
                    ? _details!.location!.location ?? 'Unknown'
                    : _unloaded,
              ),
              _field('Snapshot version', '${widget.record.version}'),
              _field(
                'Created (UTC)',
                widget.record.createdAt.toUtc().toIso8601String(),
              ),
              _field(
                'Updated (UTC)',
                widget.record.updatedAt.toUtc().toIso8601String(),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

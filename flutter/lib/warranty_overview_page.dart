import 'dart:async';

import 'package:flutter/material.dart';

import 'api/asset_warranty_overview.dart';
import 'api/asset_session.dart';
import 'api/asset_store.dart';

/// Read-only complete warranty counts; date support is gated by inventory navigation.
class WarrantyOverviewPage extends StatefulWidget {
  const WarrantyOverviewPage({super.key, required this.source});
  final AssetWarrantyOverviewSource source;

  @override
  State<WarrantyOverviewPage> createState() => _WarrantyOverviewPageState();
}

class _WarrantyOverviewPageState extends State<WarrantyOverviewPage> {
  AssetWarrantyOverview? _overview;
  String? _error;
  bool _busy = false;
  int _request = 0;

  int? _loadedRevision;
  StreamSubscription<int>? _subscription;

  void _bind() {
    final source = widget.source;
    if (source is AssetSession) {
      _subscription = (source as AssetSession).sessionChanges.listen((_) {
        if (!mounted) return;
        _request++;
        setState(() {
          _overview = null;
          _busy = false;
          _error = 'Session changed. Return to inventory and sign in again.';
        });
      });
    }
  }

  void _select(WarrantyOverviewSelection selection) {
    final source = widget.source;
    if (_busy ||
        _error != null ||
        _overview == null ||
        (source is AssetSession &&
            (source as AssetSession).sessionRevision != _loadedRevision))
      return;
    Navigator.of(context).pop(selection);
  }

  @override
  void dispose() {
    _request++;
    _subscription?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _bind();
    _load();
  }

  @override
  void didUpdateWidget(covariant WarrantyOverviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      _subscription?.cancel();
      _request++;
      _overview = null;
      _busy = false;
      _bind();
      _load();
    }
  }

  Future<void> _load() async {
    if (_busy) return;
    final source = widget.source;
    final session = source is AssetSession ? source as AssetSession : null;
    final revision = session?.sessionRevision;
    final request = ++_request;
    bool current() =>
        mounted &&
        request == _request &&
        identical(source, widget.source) &&
        (session == null || session.sessionRevision == revision);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await source.warrantyOverview();
      if (current())
        setState(() {
          _overview = result;
          _loadedRevision = revision;
        });
    } on AssetFailure catch (error) {
      if (current()) setState(() => _error = error.message);
    } catch (_) {
      if (current())
        setState(() => _error = 'Could not load warranty overview.');
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Warranty overview')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'All inventory for your account. Search, status, category and warranty list filters do not apply.',
            ),
            const SizedBox(height: 12),
            const Text(
              'View assets clears other filters and keeps this reference date. Counts and lists are separate snapshots.',
            ),
            OutlinedButton(
              onPressed: _busy ? null : _load,
              child: const Text('Refresh warranty overview'),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const Text(
                'Loading warranty overview...',
                semanticsLabel: 'Loading warranty overview',
              ),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(liveRegion: true, child: Text(_error!)),
              if (_overview != null)
                const Text(
                  'Counts below are from the last successful load and may be outdated.',
                ),
            ],
            if (_overview case final overview?) ...[
              const SizedBox(height: 16),
              Text(
                'Total assets: ${overview.total}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (overview.total == 0)
                const Text('No assets in your inventory.'),
              const SizedBox(height: 12),
              Text(
                'Reference: ${overview.asOf} UTC. Upcoming through ${overview.through}, inclusive.',
              ),
              const SizedBox(height: 16),
              Text(
                'Expired: ${overview.expired}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('Warranty ends before ${overview.asOf}.'),
              OutlinedButton(
                onPressed: _busy || _error != null
                    ? null
                    : () => _select(
                        WarrantyOverviewSelection(
                          warranty: 'expired',
                          asOf: overview.asOf,
                        ),
                      ),
                child: const Text('View expired assets'),
              ),
              const SizedBox(height: 12),
              Text(
                'Expiring within 30 days: ${overview.expiringSoon}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text(
                'Includes expiry today and the next 30 calendar days.',
              ),
              OutlinedButton(
                onPressed: _busy || _error != null
                    ? null
                    : () => _select(
                        WarrantyOverviewSelection(
                          warranty: 'expiring_soon',
                          asOf: overview.asOf,
                        ),
                      ),
                child: const Text('View assets expiring within 30 days'),
              ),
              const SizedBox(height: 12),
              Text(
                'Later: ${overview.later}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('Warranty ends after ${overview.through}.'),
              const SizedBox(height: 12),
              Text(
                'Unknown warranty date: ${overview.unknown}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text(
                'Unknown does not mean expired or covered. No automatic reminders.',
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

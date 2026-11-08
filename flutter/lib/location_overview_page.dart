import 'dart:async';

import 'package:flutter/material.dart';

import 'api/asset_location_overview.dart';
import 'api/asset_session.dart';
import 'api/asset_store.dart';

/// Explicit overview selection; null means the unknown-location bucket.
class LocationOverviewSelection {
  const LocationOverviewSelection(this.location);
  final String? location;
}

/// Complete owner inventory counts, with explicit navigation back to filtering.
class LocationOverviewPage extends StatefulWidget {
  const LocationOverviewPage({super.key, required this.source});
  final AssetLocationOverviewSource source;
  @override
  State<LocationOverviewPage> createState() => _LocationOverviewPageState();
}

class _LocationOverviewPageState extends State<LocationOverviewPage> {
  AssetLocationOverview? _overview;
  String? _error;
  bool _busy = false;
  int _request = 0;
  StreamSubscription<int>? _subscription;
  @override
  void initState() {
    super.initState();
    _bind();
    _load();
  }

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

  @override
  void didUpdateWidget(covariant LocationOverviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      _subscription?.cancel();
      _request++;
      _overview = null;
      _busy = false;
      _error = null;
      _bind();
      _load();
    }
  }

  @override
  void dispose() {
    _request++;
    _subscription?.cancel();
    super.dispose();
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
      final result = await source.locationOverview();
      if (current()) setState(() => _overview = result);
    } on AssetFailure catch (error) {
      if (current()) setState(() => _error = error.message);
    } catch (_) {
      if (current())
        setState(() => _error = 'Could not load location overview.');
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  void _select(String? label) =>
      Navigator.of(context).pop(LocationOverviewSelection(label));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Location overview')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'All inventory for your account. Current list filters do not apply.',
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : _load,
              child: const Text('Refresh location overview'),
            ),
            if (_busy) ...[
              const Text('Loading location overview...'),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
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
              const Text(
                'Choose a location to replace all inventory filters and open its assets.',
              ),
              if (overview.total == 0)
                const Text('No assets in your inventory.'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy ? null : () => _select(null),
                child: Text('Unknown location: ${overview.unknown}'),
              ),
              for (final group in overview.locations)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _select(group.location),
                    child: Text('${group.location}: ${group.count}'),
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}

import 'dart:async';

import 'package:flutter/material.dart';

import 'api/asset_overview.dart';
import 'api/asset_session.dart';
import 'api/asset_store.dart';

/// Read-only full-inventory counts; list filters and pagination are not inputs.
class InventoryOverviewPage extends StatefulWidget {
  const InventoryOverviewPage({super.key, required this.source});
  final AssetOverviewSource source;

  @override
  State<InventoryOverviewPage> createState() => _InventoryOverviewPageState();
}

class _InventoryOverviewPageState extends State<InventoryOverviewPage> {
  AssetOverview? _overview;
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

  void _select(InventoryOverviewSelection selection) {
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
  void didUpdateWidget(covariant InventoryOverviewPage oldWidget) {
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
      final result = await source.overview();
      if (current())
        setState(() {
          _overview = result;
          _loadedRevision = revision;
        });
    } on AssetFailure catch (error) {
      if (current()) setState(() => _error = error.message);
    } catch (_) {
      if (current())
        setState(() => _error = 'Could not load inventory overview.');
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Inventory overview')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'All inventory for your account. Search, status and category list filters do not apply.',
            ),
            const SizedBox(height: 12),
            const Text(
              'View assets replaces search and all other filters. Counts and lists are separate snapshots.',
            ),
            OutlinedButton(
              onPressed: _busy ? null : _load,
              child: const Text('Refresh overview'),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const Text(
                'Loading overview...',
                semanticsLabel: 'Loading overview',
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
              const SizedBox(height: 16),
              Text('By status', style: Theme.of(context).textTheme.titleMedium),
              for (final entry in overview.byStatus.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${entry.key}: ${entry.value}'),
                      OutlinedButton(
                        onPressed: _busy || _error != null
                            ? null
                            : () => _select(
                                InventoryOverviewSelection.status(entry.key),
                              ),
                        child: Text('View assets: ${entry.key}'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                'By category (exact labels)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final entry in overview.byCategory.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${entry.key}: ${entry.value}'),
                      if (entry.key.trim() == entry.key &&
                          entry.key.runes.length <= 64)
                        OutlinedButton(
                          onPressed: _busy || _error != null
                              ? null
                              : () => _select(
                                  InventoryOverviewSelection.category(
                                    entry.key,
                                  ),
                                ),
                          child: Text('View assets: ${entry.key}'),
                        )
                      else
                        const Text(
                          'This label is not supported by the current category filter.',
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}

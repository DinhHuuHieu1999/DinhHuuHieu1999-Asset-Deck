import 'dart:async';

import 'package:flutter/material.dart';

import 'api/asset_check_overview.dart';
import 'api/asset_dates.dart';
import 'api/asset_session.dart';
import 'api/asset_store.dart';

/// Complete manual check-date counts with an explicit, applied calendar cutoff.
class CheckOverviewPage extends StatefulWidget {
  const CheckOverviewPage({super.key, required this.source});
  final AssetCheckOverviewSource source;

  @override
  State<CheckOverviewPage> createState() => _CheckOverviewPageState();
}

class _CheckOverviewPageState extends State<CheckOverviewPage> {
  final _cutoff = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 10),
  );
  AssetCheckOverview? _overview;
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

  void _select(CheckOverviewSelection selection) {
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
    _cutoff.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _bind();
    _load();
  }

  @override
  void didUpdateWidget(covariant CheckOverviewPage oldWidget) {
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

  Future<void> _load({bool apply = false}) async {
    if (_busy) return;
    final cutoff = apply ? _cutoff.text : (_overview?.cutoff ?? _cutoff.text);
    if (!isAssetCalendarDate(cutoff)) {
      setState(
        () => _error = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(cutoff)
            ? 'This date does not exist. Check the day, month and year.'
            : 'Enter the cutoff date in YYYY-MM-DD format.',
      );
      return;
    }
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
      final result = await source.checkOverview(cutoff: cutoff);
      if (current())
        setState(() {
          _overview = result;
          _loadedRevision = revision;
        });
    } on AssetFailure catch (error) {
      if (current()) setState(() => _error = error.message);
    } catch (_) {
      if (current())
        setState(() => _error = 'Could not load check-date overview.');
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Check-date overview')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'All inventory for your account, not the current list filters. Dates are manual assertions, not inspection proof.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cutoff,
              enabled: !_busy,
              maxLength: 10,
              decoration: const InputDecoration(
                labelText: 'Cutoff date (draft)',
                hintText: 'YYYY-MM-DD',
              ),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _load(apply: true),
              child: const Text('Apply cutoff'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : _load,
              child: const Text('Refresh check-date overview'),
            ),
            const Text(
              'Starts with your local date when opened. Apply uses the entered date; Refresh uses the last applied cutoff and keeps your draft.',
            ),
            if (_busy) ...[
              const Text('Loading check-date overview...'),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
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
              Text('Applied cutoff: ${overview.cutoff}'),
              const Text(
                'View assets clears other filters and keeps applied sort. Counts and lists are separate snapshots.',
              ),
              for (final bucket in [
                ('unchecked', 'Unknown check date', overview.unknown),
                ('before', 'Before cutoff', overview.before),
                ('on_or_after', 'On or after cutoff', overview.onOrAfter),
              ]) ...[
                const SizedBox(height: 16),
                Text(
                  '${bucket.$2}: ${bucket.$3}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                OutlinedButton(
                  onPressed: _busy || _error != null
                      ? null
                      : () => _select(
                          CheckOverviewSelection(
                            mode: bucket.$1,
                            cutoff: overview.cutoff,
                          ),
                        ),
                  child: Text('View assets: ${bucket.$2}'),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Unknown dates do not mean overdue. No automatic reminders.',
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

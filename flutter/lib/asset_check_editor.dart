import 'package:flutter/material.dart';

import 'api/asset_check.dart';
import 'api/asset_dates.dart';
import 'api/asset_store.dart';

/// Manual check-date replacement; failed or conflicting writes preserve the draft.
class AssetCheckEditor extends StatefulWidget {
  const AssetCheckEditor({
    super.key,
    required this.source,
    required this.original,
  });
  final AssetCheckSource source;
  final AssetCheck original;
  @override
  State<AssetCheckEditor> createState() => _AssetCheckEditorState();
}

class _AssetCheckEditorState extends State<AssetCheckEditor> {
  late final TextEditingController _date;
  bool _busy = false, _leaving = false, _uncertain = false;
  String? _error;
  bool get _dirty => _date.text != (widget.original.lastCheckedOn ?? '');
  @override
  void initState() {
    super.initState();
    _date = TextEditingController(text: widget.original.lastCheckedOn ?? '')
      ..addListener(_changed);
  }

  void _changed() => setState(() {});
  @override
  void dispose() {
    _date.dispose();
    super.dispose();
  }

  void _leave(bool saved) {
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, saved);
    });
  }

  Future<void> _back() async {
    if (_busy) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard unsaved changes?'),
          content: const Text(
            'Keep editing to preserve this check-date draft.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (mounted) _leave(false);
  }

  Future<void> _save() async {
    if (_busy || _uncertain) return;
    final date = _date.text.isEmpty ? null : _date.text;
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    if (date != null &&
        (!isAssetCalendarDate(date) || date.compareTo(today) > 0)) {
      setState(
        () => _error = 'Enter a real date as YYYY-MM-DD, no later than today (UTC), or leave blank to clear.',
      );
      return;
    }
    try {
      widget.original.replacement(date);
    } on FormatException {
      setState(
        () => _error = 'Asset version cannot be edited. Return and refresh.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.source.updateCheckDate(widget.original, date);
      if (!mounted) return;
      _busy = false;
      _leave(true);
    } catch (error) {
      if (!mounted) return;
      final conflict = error is AssetFailure && error.statusCode == 409;
      final rejected =
          error is AssetFailure &&
          (error.definitelyNotSent ||
              [400, 401, 403, 409, 422].contains(error.statusCode));
      setState(() {
        _busy = false;
        _uncertain = conflict || !rejected;
        _error = conflict
            ? 'Asset changed or is unavailable. Draft preserved; return and refresh before editing again.'
            : rejected
            ? error.message
            : 'Save outcome unknown. Draft preserved; return and refresh before another write. No automatic retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: _leaving || (!_dirty && !_busy),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _back();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Last inventory check'),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _busy ? null : _back,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Use YYYY-MM-DD. Manual date only, not proof of inspection. Dates use the UTC calendar day; future dates are rejected. Blank clears the date.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _date,
                enabled: !_busy,
                maxLength: 10,
                decoration: const InputDecoration(
                  labelText: 'Check date',
                  border: OutlineInputBorder(),
                ),
              ),
              const Text(
                'Existing inventory JSON exports exclude check dates. They are not check-date backups.',
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Text(
                      'Error: $_error',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              if (_busy)
                const LinearProgressIndicator(
                  semanticsLabel: 'Saving check date',
                ),
              FilledButton(
                onPressed: _busy || _uncertain ? null : _save,
                child: const Text('Save check date'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _back,
                child: const Text('Cancel'),
              ),
              const Text(
                'Only the check date changes. No automatic retries or queued offline writes.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

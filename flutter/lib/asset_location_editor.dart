import 'package:flutter/material.dart';

import 'api/asset_location.dart';
import 'api/asset_store.dart';

/// Manual location replacement; failed or conflicting writes preserve the draft.
class AssetLocationEditor extends StatefulWidget {
  const AssetLocationEditor({
    super.key,
    required this.source,
    required this.original,
  });
  final AssetLocationSource source;
  final AssetLocation original;
  @override
  State<AssetLocationEditor> createState() => _AssetLocationEditorState();
}

class _AssetLocationEditorState extends State<AssetLocationEditor> {
  late final TextEditingController _location;
  bool _busy = false, _leaving = false, _uncertain = false;
  String? _error;
  bool get _dirty => _location.text != (widget.original.location ?? '');
  @override
  void initState() {
    super.initState();
    _location = TextEditingController(text: widget.original.location ?? '')
      ..addListener(_changed);
  }

  void _changed() => setState(() {});
  @override
  void dispose() {
    _location.dispose();
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
          content: const Text('Keep editing to preserve this location draft.'),
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
    String? location;
    try {
      location = normalizeAssetLocation(
        _location.text.trim().isEmpty ? null : _location.text,
      );
      widget.original.replacement(location);
    } on FormatException {
      setState(
        () => _error = 'Use a location up to 120 characters without control characters, or leave blank to clear.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.source.updateLocation(widget.original, location);
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
        title: const Text('Asset location'),
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
                'Manual label only. No GPS, device discovery or background tracking. Blank clears the location.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _location,
                enabled: !_busy,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  border: OutlineInputBorder(),
                ),
              ),
              const Text(
                'Inventory JSON v1 and v2 exclude location labels. They are not location backups.',
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Text(_error!, semanticsLabel: 'Error: $_error'),
              if (_busy)
                const LinearProgressIndicator(
                  semanticsLabel: 'Saving location',
                ),
              FilledButton(
                onPressed: _busy || _uncertain ? null : _save,
                child: const Text('Save location'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _back,
                child: const Text('Cancel'),
              ),
              const Text(
                'Only location changes. No automatic retries or queued offline writes.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

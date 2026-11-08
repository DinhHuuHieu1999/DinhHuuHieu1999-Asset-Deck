import 'package:flutter/material.dart';

import 'api/asset_dates.dart';
import 'api/asset_store.dart';

/// Separate date edit form using a freshly loaded shared asset version. Failed writes are never automatically retried.
class AssetDatesEditor extends StatefulWidget {
  const AssetDatesEditor({
    super.key,
    required this.store,
    required this.original,
  });
  final AssetDatesSource store;
  final AssetDates original;
  @override
  State<AssetDatesEditor> createState() => _AssetDatesEditorState();
}

class _AssetDatesEditorState extends State<AssetDatesEditor> {
  late final TextEditingController _purchase, _warranty;
  bool _busy = false, _saved = false, _uncertain = false;
  String? _error;
  AssetDatesInput get _input => AssetDatesInput(
    purchasedOn: _purchase.text.isEmpty ? null : _purchase.text,
    warrantyExpiresOn: _warranty.text.isEmpty ? null : _warranty.text,
  );
  bool get _dirty =>
      _purchase.text != (widget.original.input.purchasedOn ?? '') ||
      _warranty.text != (widget.original.input.warrantyExpiresOn ?? '');

  @override
  void initState() {
    super.initState();
    _purchase = TextEditingController(
      text: widget.original.input.purchasedOn ?? '',
    );
    _warranty = TextEditingController(
      text: widget.original.input.warrantyExpiresOn ?? '',
    );
    _purchase.addListener(_changed);
    _warranty.addListener(_changed);
  }

  void _changed() {
    setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_purchase, _warranty]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _back() async {
    if (_busy) return;
    if (_dirty && !_saved) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard unsaved changes?'),
          content: const Text('Keep editing to preserve this draft.'),
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

  void _leave(bool result) {
    setState(() => _saved = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, result);
    });
  }

  Future<void> _save() async {
    if (_busy || _uncertain) return;
    final input = _input;
    try {
      input.toJson(version: widget.original.version);
    } on FormatException {
      setState(
        () => _error = 'Use real YYYY-MM-DD dates or leave blank. Warranty must not precede purchase.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.updateDates(widget.original, input);
      if (!mounted) return;
      setState(() {
        _saved = true;
        _busy = false;
      });
      _leave(true);
    } catch (error) {
      if (!mounted) return;
      final conflict = error is AssetFailure && error.statusCode == 409;
      final rejected =
          error is AssetFailure &&
          [400, 401, 403, 409, 422].contains(error.statusCode);
      setState(() {
        _busy = false;
        _uncertain = conflict || !rejected;
        _error = conflict
            ? 'The record changed or is unavailable. Your draft is preserved. Return to inventory and refresh before editing again.'
            : rejected
            ? error.message
            : 'Save outcome is unknown. Your draft is preserved. Return to inventory and refresh before another write; do not submit again blindly.';
      });
    }
  }

  Widget _field(
    String label,
    TextEditingController controller,
    int limit, {
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      enabled: !_busy,
      maxLength: limit,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: _saved || (!_dirty && !_busy),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _back();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Asset dates'),
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
                'Use YYYY-MM-DD for optional calendar dates. Blank clears a date. No reminders are scheduled.',
              ),
              const SizedBox(height: 12),
              _field('Purchased on', _purchase, 10),
              _field('Warranty ends', _warranty, 10),
              const Text(
                'Inventory export JSON v1 excludes these dates. It is not a warranty backup.',
              ),
              const SizedBox(height: 12),
              if (_error != null) Text(_error!),
              if (_busy)
                const LinearProgressIndicator(semanticsLabel: 'Saving dates'),
              FilledButton(
                onPressed: _busy || _uncertain ? null : _save,
                child: const Text('Save dates'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _back,
                child: const Text('Cancel'),
              ),
              const Text(
                'Only dates are changed. No automatic retries or queued offline writes.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

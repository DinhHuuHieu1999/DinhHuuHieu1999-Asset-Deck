import 'package:flutter/material.dart';

import 'api/asset.dart';
import 'api/asset_store.dart';
import 'api/asset_serial_check.dart';
import 'api/asset_session.dart';

/// Manual create/edit form. Failed writes are never automatically retried.
class AssetEditor extends StatefulWidget {
  const AssetEditor({super.key, required this.store, this.original})
    : draft = null;

  /// Create-only draft: deliberately excludes identity, serial and optional data.
  AssetEditor.duplicate({
    super.key,
    required this.store,
    required AssetRecord source,
  }) : original = null,
       draft = AssetInput(
         name: source.input.name,
         category: source.input.category,
         serial: '',
         status: source.input.status,
         notes: source.input.notes,
       );
  final AssetInput? draft;
  final AssetStore store;
  final AssetRecord? original;
  @override
  State<AssetEditor> createState() => _AssetEditorState();
}

class _AssetEditorState extends State<AssetEditor> {
  late final TextEditingController _name, _category, _serial, _notes;
  late String _status;
  bool _busy = false, _saved = false, _uncertain = false;
  String? _error;
  int _serialRequest = 0;
  bool _checkingSerial = false, _serialCheckFailed = false;
  bool? _serialDuplicate;
  String _lastSerial = '';
  AssetSerialCheckSource? get _serialSource =>
      widget.store is AssetSerialCheckSource
      ? widget.store as AssetSerialCheckSource
      : null;
  AssetInput get _input => AssetInput(
    name: _name.text,
    category: _category.text,
    serial: _serial.text,
    status: _status,
    notes: _notes.text,
  );
  bool get _dirty {
    final initial = widget.original?.input;
    return _name.text != (initial?.name ?? '') ||
        _category.text != (initial?.category ?? '') ||
        _serial.text != (initial?.serial ?? '') ||
        _notes.text != (initial?.notes ?? '') ||
        _status != (initial?.status ?? 'in_use');
  }

  @override
  void initState() {
    super.initState();
    final i = widget.original?.input ?? widget.draft;
    _name = TextEditingController(text: i?.name ?? '');
    _category = TextEditingController(text: i?.category ?? '');
    _serial = TextEditingController(text: i?.serial ?? '');
    _lastSerial = _serial.text;
    _notes = TextEditingController(text: i?.notes ?? '');
    _status = i?.status ?? 'in_use';
    for (final c in [_name, _category, _serial, _notes]) {
      c.addListener(_changed);
    }
  }

  void _changed() {
    if (_lastSerial != _serial.text) {
      _lastSerial = _serial.text;
      _serialRequest++;
      _checkingSerial = false;
      _serialDuplicate = null;
      _serialCheckFailed = false;
    }
    setState(() {});
  }

  Future<void> _checkSerial() async {
    final source = _serialSource;
    final serial = _serial.text.trim();
    if (source == null || _busy || _checkingSerial || serial.isEmpty) return;
    final request = ++_serialRequest;
    final session = widget.store is AssetSession
        ? widget.store as AssetSession
        : null;
    final revision = session?.sessionRevision;
    bool current() =>
        mounted &&
        request == _serialRequest &&
        identical(source, _serialSource) &&
        revision == session?.sessionRevision;
    setState(() {
      _checkingSerial = true;
      _serialDuplicate = null;
      _serialCheckFailed = false;
    });
    try {
      if (serial.runes.length > 120 || serial.contains('\u0000')) {
        throw const FormatException('Invalid serial');
      }
      final duplicate = await source.serialDuplicate(
        serial,
        excludeId: widget.original?.id,
      );
      if (current()) setState(() => _serialDuplicate = duplicate);
    } catch (_) {
      if (current()) setState(() => _serialCheckFailed = true);
    } finally {
      if (mounted && request == _serialRequest) {
        setState(() => _checkingSerial = false);
      }
    }
  }

  Widget _serialCheck() {
    final scheme = Theme.of(context).colorScheme;
    final warning = ColorScheme.fromSeed(
      seedColor: Colors.amber,
      brightness: scheme.brightness,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton(
          onPressed: _busy || _checkingSerial || _serial.text.trim().isEmpty
              ? null
              : _checkSerial,
          child: const Text('Check duplicate serial'),
        ),
        if (_checkingSerial)
          const LinearProgressIndicator(semanticsLabel: 'Checking serial'),
        if (_serialDuplicate != null || _serialCheckFailed)
          Semantics(
            liveRegion: true,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _serialCheckFailed
                    ? scheme.errorContainer
                    : _serialDuplicate == true
                    ? warning.primaryContainer
                    : scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _serialCheckFailed
                    ? 'Serial check unavailable. Your draft is kept; saving is still allowed.'
                    : _serialDuplicate!
                    ? 'Duplicate serial found in your inventory. Saving is still allowed.'
                    : 'No other asset currently has this exact serial. This is not a uniqueness guarantee.',
                style: TextStyle(
                  color: _serialCheckFailed
                      ? scheme.onErrorContainer
                      : _serialDuplicate == true
                      ? warning.onPrimaryContainer
                      : scheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
        const Text(
          'Optional exact, case-sensitive check. Other accounts are never searched.',
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  void dispose() {
    _serialRequest++;
    for (final c in [_name, _category, _serial, _notes]) {
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
      input.toJson();
    } on FormatException {
      setState(
        () => _error = 'Enter a name and category within the displayed limits. NUL is not allowed.',
      );
      return;
    }
    _serialRequest++;
    setState(() {
      _checkingSerial = false;
      _serialDuplicate = null;
      _serialCheckFailed = false;
      _busy = true;
      _error = null;
    });
    try {
      final original = widget.original;
      if (original == null) {
        await widget.store.create(input);
      } else {
        await widget.store.update(original, input);
      }
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
        title: Text(
          widget.draft != null
              ? 'Duplicate asset draft'
              : widget.original == null
              ? 'Add asset'
              : 'Edit asset',
        ),
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
              if (widget.draft != null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'New unsaved asset. Serial is blank; dates, location and check date are not copied. Review before Save.',
                  ),
                ),
              _field('Name (required)', _name, 120),
              _field('Category (required)', _category, 64),
              _field('Serial (optional)', _serial, 120),
              if (_serialSource != null) _serialCheck(),
              DropdownButtonFormField<String>(
                initialValue: _status,
                isExpanded: true,
                itemHeight: null,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: assetStatuses
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: _busy
                    ? null
                    : (s) => setState(() => _status = s ?? _status),
              ),
              const SizedBox(height: 12),
              _field('Notes (optional)', _notes, 2000, lines: 4),
              if (_error != null) Text(_error!),
              if (_busy)
                const LinearProgressIndicator(semanticsLabel: 'Saving asset'),
              FilledButton(
                onPressed: _busy || _uncertain ? null : _save,
                child: const Text('Save asset'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _back,
                child: const Text('Cancel'),
              ),
              const Text(
                'Duplicate names and serials are allowed. No automatic retries or queued offline writes.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

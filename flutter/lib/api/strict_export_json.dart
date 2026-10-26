import 'dart:convert';

/// Adapted from ToolDeck strict_catalog_json.dart; reject duplicate keys and deep JSON.
Object? decodeAssetExportJson(String source) =>
    _decodeBoundedJson(source, 1024 * 1024);

/// Separate recovery envelope bound; inventory export keeps its original 1 MiB.
Object? decodeAssetRecoveryJson(String source) =>
    _decodeBoundedJson(source, 2 * 1024 * 1024);

Object? _decodeBoundedJson(String source, int limit) {
  if (source.length > limit || utf8.encode(source).length > limit) {
    throw const FormatException('Inventory JSON exceeds size limit');
  }
  _CatalogJsonGuard(source).check();
  return jsonDecode(source);
}

// Scan structure before the SDK decoder so duplicate keys and nesting limits
// cannot disappear during Map construction. The SDK still validates tokens.
class _CatalogJsonGuard {
  _CatalogJsonGuard(this.source);
  final String source;
  int offset = 0;

  Never _invalid() => throw const FormatException('Invalid inventory JSON');

  void _space() {
    while (offset < source.length &&
        const [0x20, 0x09, 0x0a, 0x0d].contains(source.codeUnitAt(offset))) {
      offset++;
    }
  }

  bool _take(String token) {
    _space();
    if (offset < source.length && source[offset] == token) {
      offset++;
      return true;
    }
    return false;
  }

  String _string() {
    _space();
    final start = offset;
    if (offset >= source.length || source[offset++] != '"') _invalid();
    while (offset < source.length) {
      final character = source[offset++];
      if (character == '"') {
        final decoded = jsonDecode(source.substring(start, offset)) as String;
        for (var i = 0; i < decoded.length; i++) {
          final unit = decoded.codeUnitAt(i);
          if (unit >= 0xd800 && unit <= 0xdbff) {
            if (++i >= decoded.length) _invalid();
            final low = decoded.codeUnitAt(i);
            if (low < 0xdc00 || low > 0xdfff) _invalid();
          } else if (unit >= 0xdc00 && unit <= 0xdfff) {
            _invalid();
          }
        }
        return decoded;
      }
      if (character == r'\') {
        if (offset >= source.length) _invalid();
        offset++;
      }
    }
    _invalid();
  }

  void _value(int depth) {
    if (depth > 32) _invalid();
    _space();
    if (offset >= source.length) _invalid();
    if (_take('{')) {
      final keys = <String>{};
      if (_take('}')) return;
      do {
        if (!keys.add(_string()) || !_take(':')) _invalid();
        _value(depth + 1);
        if (_take('}')) return;
      } while (_take(','));
      _invalid();
    }
    if (_take('[')) {
      if (_take(']')) return;
      do {
        _value(depth + 1);
        if (_take(']')) return;
      } while (_take(','));
      _invalid();
    }
    if (source[offset] == '"') {
      _string();
      return;
    }
    final start = offset;
    while (offset < source.length &&
        !const [
          ' ',
          '\t',
          '\r',
          '\n',
          ',',
          '}',
          ']',
        ].contains(source[offset])) {
      offset++;
    }
    if (offset == start) _invalid();
    final token = jsonDecode(source.substring(start, offset));
    if (token is num && !token.isFinite) _invalid();
  }

  void check() {
    _value(0);
    _space();
    if (offset != source.length) _invalid();
  }
}

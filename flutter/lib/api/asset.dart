/// Manual equipment states; none schedules work or invokes a tool.
const assetStatuses = ['in_use', 'stored', 'repair', 'retired'];

/// Editable fields only: identity and ownership are supplied by the server.
class AssetInput {
  const AssetInput({
    required this.name,
    required this.category,
    this.serial = '',
    required this.status,
    this.notes = '',
  });
  final String name, category, serial, status, notes;

  Map<String, Object?> toJson() {
    final values = [name, category, serial, notes];
    final limits = [120, 64, 120, 2000];
    for (var i = 0; i < values.length; i++) {
      if (values[i].length > limits[i] || values[i].contains('\u0000')) {
        throw const FormatException('Invalid asset input');
      }
    }
    if (name.trim().isEmpty ||
        category.trim().isEmpty ||
        !assetStatuses.contains(status)) {
      throw const FormatException('Invalid asset input');
    }
    return {
      'name': name.trim(),
      'category': category.trim(),
      'serial': serial.trim(),
      'status': status,
      'notes': notes.trim(),
    };
  }
}

/// Server-owned identity and version for an equipment record.
class AssetRecord {
  const AssetRecord({
    required this.id,
    required this.input,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final AssetInput input;
  final int version;
  final DateTime createdAt, updatedAt;

  factory AssetRecord.fromJson(Map<String, Object?> json) {
    String field(String name) {
      final value = json[name];
      if (value is! String) throw const FormatException('Invalid asset field');
      return value;
    }

    final input = AssetInput(
      name: field('name'),
      category: field('category'),
      serial: field('serial'),
      status: field('status'),
      notes: field('notes'),
    );
    input.toJson();
    final id = field('id');
    final version = json['version'];
    final created = DateTime.tryParse(field('createdAt'));
    final updated = DateTime.tryParse(field('updatedAt'));
    if (!RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(id) ||
        version is! int ||
        version < 1 ||
        version > 2147483647 ||
        created == null ||
        updated == null ||
        !created.isUtc ||
        !updated.isUtc) {
      throw const FormatException('Invalid asset metadata');
    }
    return AssetRecord(
      id: id,
      input: input,
      version: version,
      createdAt: created,
      updatedAt: updated,
    );
  }
}

/// One bounded page; an absent continuation does not imply a full export.
class AssetPage {
  AssetPage(List<AssetRecord> records, this.nextOffset)
    : items = List.unmodifiable(records);
  final List<AssetRecord> items;
  final int? nextOffset;

  factory AssetPage.fromJson(Map<String, Object?> json, {required int offset}) {
    if (offset < 0 || offset > 100000) {
      throw const FormatException('Invalid page offset');
    }
    final items = json['items'];
    final next = json['nextOffset'];
    if (items is! List ||
        items.length > 50 ||
        !json.containsKey('nextOffset') ||
        (next != null &&
            (next is! int || next != offset + 50 || next > 100000))) {
      throw const FormatException('Invalid asset page');
    }
    final records = items
        .map((item) {
          if (item is! Map<String, Object?>) {
            throw const FormatException('Invalid asset record');
          }
          return AssetRecord.fromJson(item);
        })
        .toList(growable: false);
    if (records.map((r) => r.id.toLowerCase()).toSet().length !=
            records.length ||
        (next != null && records.length != 50)) {
      throw const FormatException('Invalid asset continuation');
    }
    return AssetPage(records, next as int?);
  }
}

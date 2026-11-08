import 'dart:convert';
import 'dart:typed_data';

import 'asset_selection_export_v2.dart';

/// Spreadsheet convenience projection, not a checksum envelope or import format.
class AssetSelectionCsv {
  AssetSelectionCsv._(this.text, this.count, this.protectedCells);
  final String text;
  final int count, protectedCells;

  /// Return a fresh UTF-8 buffer; callers cannot mutate the prepared document.
  Uint8List get bytes => Uint8List.fromList(utf8.encode(text));

  /// Convert only a verified, complete selection; refuse oversized CSV output.
  factory AssetSelectionCsv.fromSelection(AssetSelectionExportV2 snapshot) {
    var protected = 0;
    String cell(String value) {
      // Quoting alone does not prevent spreadsheet formula interpretation.
      // Cover leading whitespace/control and common full-width formula markers.
      final leading = value.trimLeft();
      if (RegExp(r'^[=+@\-＝＋＠－]').hasMatch(leading) ||
          RegExp(r'^[\x00-\x1f]').hasMatch(value)) {
        value = "'$value";
        protected++;
      }
      return '"${value.replaceAll('"', '""')}"';
    }

    final output = StringBuffer();
    void row(List<String> cells) =>
        output.write('${cells.map(cell).join(',')}\r\n');
    row([
      'id',
      'name',
      'category',
      'serial',
      'status',
      'notes',
      'purchasedOn',
      'warrantyExpiresOn',
      'location',
      'lastCheckedDate',
      'version',
      'createdAt',
      'updatedAt',
    ]);
    for (final item in snapshot.records) {
      final record = item.record;
      final asset = record.asset;
      row([
        asset.id,
        asset.input.name,
        asset.input.category,
        asset.input.serial,
        asset.input.status,
        asset.input.notes,
        record.dates.purchasedOn ?? '',
        record.dates.warrantyExpiresOn ?? '',
        record.location ?? '',
        item.lastCheckedDate ?? '',
        asset.version.toString(),
        asset.createdAt.toIso8601String(),
        asset.updatedAt.toIso8601String(),
      ]);
    }
    final text = output.toString();
    if (snapshot.count > 500 || utf8.encode(text).length > 1024 * 1024) {
      throw const FormatException('Selection CSV exceeds export limits');
    }
    return AssetSelectionCsv._(text, snapshot.count, protected);
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../app_scope.dart';
import 'widgets/dialogs.dart';

/// Genera un CSV compatibile con Excel in italiano: separatore ";",
/// codifica UTF-8 con BOM, righe CRLF.
Uint8List buildCsv(List<String> header, Iterable<List<Object?>> rows) {
  String cell(Object? value) {
    final text = value?.toString() ?? '';
    final needsQuotes =
        text.contains(';') ||
        text.contains('"') ||
        text.contains('\n') ||
        text.contains('\r');
    final escaped = text.replaceAll('"', '""');
    return needsQuotes ? '"$escaped"' : escaped;
  }

  final buffer = StringBuffer()..write(header.map(cell).join(';'));
  for (final row in rows) {
    buffer
      ..write('\r\n')
      ..write(row.map(cell).join(';'));
  }
  buffer.write('\r\n');
  return Uint8List.fromList([
    0xEF,
    0xBB,
    0xBF,
    ...utf8.encode(buffer.toString()),
  ]);
}

/// Nome file con data e ora: `prefisso_20260924_1730.csv`.
String timestampedFileName(
  String prefix,
  DateTime now, {
  String extension = 'csv',
}) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${prefix}_${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}.$extension';
}

/// Chiede dove salvare il CSV e lo scrive.
Future<void> saveCsv(
  BuildContext context, {
  required String fileName,
  required Uint8List bytes,
}) async {
  try {
    final path = await context.deps.files.saveFile(
      suggestedName: fileName,
      bytes: bytes,
      mimeType: 'text/csv',
    );
    if (path != null && context.mounted) {
      showMessage(context, 'Esportazione salvata in $path');
    }
  } catch (_) {
    if (context.mounted) {
      showMessage(context, 'Impossibile salvare il file.', error: true);
    }
  }
}

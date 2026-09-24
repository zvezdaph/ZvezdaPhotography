import 'dart:convert';
import 'dart:typed_data';

/// Genera un PDF di una pagina con testo semplice (Helvetica, WinAnsi).
///
/// Serve al mock per restituire un file apribile quando si scarica un
/// documento dimostrativo. SOLO DEMO.
Uint8List buildDemoPdf({required String title, required List<String> lines}) {
  final content = StringBuffer()
    ..writeln('BT')
    ..writeln('/F1 9 Tf 0.75 0 0 rg 56 800 Td')
    ..writeln(
      '(${_escape('DOCUMENTO DIMOSTRATIVO - DATI FITTIZI - PeopleCare Central Operations')}) Tj',
    )
    ..writeln('ET')
    ..writeln('BT')
    ..writeln('/F2 18 Tf 0.05 0.25 0.3 rg 56 760 Td')
    ..writeln('(${_escape(title)}) Tj')
    ..writeln('ET')
    ..writeln('BT')
    ..writeln('/F1 11 Tf 0.1 0.1 0.1 rg 56 725 Td 16 TL');
  for (final line in lines) {
    content.writeln('(${_escape(line)}) Tj T*');
  }
  content.writeln('ET');
  final stream = latin1.encode(content.toString());

  final objects = <List<int>>[
    latin1.encode('<< /Type /Catalog /Pages 2 0 R >>'),
    latin1.encode('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
    latin1.encode(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
      '/Contents 4 0 R /Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> >>',
    ),
    [
      ...latin1.encode('<< /Length ${stream.length} >>\nstream\n'),
      ...stream,
      ...latin1.encode('\nendstream'),
    ],
    latin1.encode(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
      '/Encoding /WinAnsiEncoding >>',
    ),
    latin1.encode(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold '
      '/Encoding /WinAnsiEncoding >>',
    ),
  ];

  final bytes = BytesBuilder()..add(latin1.encode('%PDF-1.4\n'));
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(bytes.length);
    bytes
      ..add(latin1.encode('${i + 1} 0 obj\n'))
      ..add(objects[i])
      ..add(latin1.encode('\nendobj\n'));
  }
  final xrefOffset = bytes.length;
  final xref = StringBuffer()
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    xref.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  xref
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  bytes.add(latin1.encode(xref.toString()));
  return bytes.toBytes();
}

/// Escape per le stringhe PDF; i caratteri fuori da Latin-1 diventano '?'.
String _escape(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    if (rune == 0x28 || rune == 0x29 || rune == 0x5C) {
      buffer.write('\\${String.fromCharCode(rune)}');
    } else if (rune == 0x2014 || rune == 0x2013) {
      buffer.write('-');
    } else if (rune > 0xFF) {
      buffer.write('?');
    } else {
      buffer.write(String.fromCharCode(rune));
    }
  }
  return buffer.toString();
}

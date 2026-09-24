import 'dart:convert';

import 'app_logger.dart';

/// Builds the text copied by "COPIA REPORT DIAGNOSTICO". It never contains
/// tokens, passphrases or stream keys: only states, versions and redacted logs.
class DiagnosticsReport {
  static String build({
    required DateTime now,
    required Map<String, Object?> app,
    required Map<String, Object?> device,
    required Map<String, Object?> engine,
    required Map<String, Object?> control,
    required List<LogEntry> logs,
  }) {
    final buffer = StringBuffer()
      ..writeln('=== PeopleCare Remote Camera — report diagnostico ===')
      ..writeln('Generato: ${now.toIso8601String()}')
      ..writeln()
      ..writeln('[App]')
      ..writeln(_section(app))
      ..writeln('[Dispositivo]')
      ..writeln(_section(device))
      ..writeln('[Motore camera/stream]')
      ..writeln(_section(engine))
      ..writeln('[Regia / Cloudflare]')
      ..writeln(_section(control))
      ..writeln('[Log recenti]');
    for (final entry in logs) {
      buffer.writeln(entry.format());
    }
    return Redactor.redact(buffer.toString());
  }

  static String _section(Map<String, Object?> values) {
    final lines = <String>[];
    values.forEach((key, value) {
      final text = value is Map || value is List ? jsonEncode(value) : '$value';
      lines.add('  $key: $text');
    });
    return lines.join('\n');
  }
}

import 'dart:collection';

import 'package:flutter/foundation.dart';

enum LogLevel {
  info('INFO'),
  warning('WARNING'),
  error('ERROR');

  const LogLevel(this.label);
  final String label;

  static LogLevel parse(Object? value) => switch (value) {
        'error' => LogLevel.error,
        'warning' => LogLevel.warning,
        _ => LogLevel.info,
      };
}

class LogEntry {
  const LogEntry(this.time, this.level, this.source, this.message, {this.code});
  final DateTime time;
  final LogLevel level;
  final String source;
  final String message;
  final String? code;

  String format() {
    final t = time.toIso8601String().substring(11, 23);
    return '$t ${level.label.padRight(7)} [$source] ${code != null ? '($code) ' : ''}$message';
  }
}

/// Removes secrets from any text before it is logged or copied.
class Redactor {
  static final List<(RegExp, String)> _rules = [
    (RegExp(r'(passphrase=)[^&\s]+', caseSensitive: false), r'$1***'),
    (RegExp(r'(streamid=)[^&\s]+', caseSensitive: false), r'$1***'),
    (RegExp(r'(Bearer\s+)[A-Za-z0-9._~+/=-]+', caseSensitive: false), r'$1***'),
    (RegExp(r'((?:rtmps?|srt)://[^/\s]+/[^/\s]+/)[^\s]+', caseSensitive: false), r'$1***'),
    (RegExp(r'("?(?:deviceToken|pollToken|passphrase|streamKey|token)"?\s*[:=]\s*"?)[^",\s}&]+', caseSensitive: false),
        r'$1***'),
    // Long opaque strings (tokens, keys): keep only a short prefix.
    (RegExp(r'\b([A-Za-z0-9_-]{6})[A-Za-z0-9_-]{26,}\b'), r'$1…'),
  ];

  static String redact(String input) {
    var output = input;
    for (final (pattern, replacement) in _rules) {
      output = output.replaceAllMapped(pattern, (m) {
        var result = replacement;
        for (var i = 1; i <= m.groupCount; i++) {
          result = result.replaceAll('\$$i', m.group(i) ?? '');
        }
        return result;
      });
    }
    return output;
  }
}

/// In-memory ring buffer of readable logs (INFO / WARNING / ERROR).
class AppLogger extends ChangeNotifier {
  AppLogger({this.capacity = 600});

  final int capacity;
  final ListQueue<LogEntry> _entries = ListQueue<LogEntry>();

  List<LogEntry> get entries => List.unmodifiable(_entries);

  void log(LogLevel level, String source, String message, {String? code}) {
    _entries.addLast(LogEntry(DateTime.now(), level, source, Redactor.redact(message), code: code));
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    notifyListeners();
  }

  void info(String source, String message) => log(LogLevel.info, source, message);
  void warning(String source, String message, {String? code}) => log(LogLevel.warning, source, message, code: code);
  void error(String source, String message, {String? code}) => log(LogLevel.error, source, message, code: code);

  List<LogEntry> recent({int limit = 100, LogLevel? minLevel}) {
    final filtered = minLevel == null ? _entries : _entries.where((e) => e.level.index >= minLevel.index);
    final list = filtered.toList();
    return list.length > limit ? list.sublist(list.length - limit) : list;
  }
}

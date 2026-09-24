import 'package:intl/intl.dart';

import '../../domain/domain.dart';

/// Formattazione in italiano di date, orari e quantità.
///
/// Richiede `initializeDateFormatting('it_IT')` all'avvio (vedi bootstrap).
abstract final class Fmt {
  static const locale = 'it_IT';

  static final _date = DateFormat('dd/MM/yyyy', locale);
  static final _dateShort = DateFormat('dd/MM', locale);
  static final _time = DateFormat('HH:mm', locale);
  static final _dayLong = DateFormat('EEEE d MMMM y', locale);
  static final _dayMedium = DateFormat('EEE d MMM', locale);
  static final _dayHeader = DateFormat('EEE d', locale);
  static final _monthYear = DateFormat('MMMM y', locale);
  static final _weekdayShort = DateFormat('EEE', locale);
  static final _number = NumberFormat.decimalPattern(locale);
  static final _oneDecimal = NumberFormat('#,##0.0', locale);

  static String date(DateTime value) => _date.format(value);

  static String dateShort(DateTime value) => _dateShort.format(value);

  static String time(DateTime value) => _time.format(value);

  static String dateTime(DateTime value) =>
      '${_date.format(value)} ${_time.format(value)}';

  /// "giovedì 24 settembre 2026"
  static String dayLong(DateTime value) => _dayLong.format(value);

  /// "gio 24 set"
  static String dayMedium(DateTime value) => _dayMedium.format(value);

  /// "gio 24"
  static String dayHeader(DateTime value) => _dayHeader.format(value);

  /// "settembre 2026"
  static String monthYear(DateTime value) =>
      capitalize(_monthYear.format(value));

  static String weekdayShort(DateTime value) => _weekdayShort.format(value);

  /// "08:30–09:15", con la data se il servizio finisce un altro giorno.
  static String timeRange(DateTime start, DateTime end) {
    if (isSameDay(start, end) ||
        (end.hour == 0 &&
            end.minute == 0 &&
            end.difference(start).inHours < 24)) {
      return '${time(start)}–${time(end)}';
    }
    return '${time(start)}–${dateShort(end)} ${time(end)}';
  }

  /// "gio 24 set, 08:30–09:15"
  static String slot(DateTime start, DateTime end) =>
      '${capitalize(dayMedium(start))}, ${timeRange(start, end)}';

  /// "45 min", "1 h 30 min", "2 h"
  static String duration(Duration value) {
    final minutes = value.inMinutes.abs();
    final sign = value.isNegative ? '-' : '';
    if (minutes < 60) return '$sign$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$sign$h h' : '$sign$h h $m min';
  }

  /// Ore con un decimale: "12,5 h".
  static String hoursFromMinutes(int minutes) =>
      '${_oneDecimal.format(minutes / 60)} h';

  /// "+12 min" / "-3 min" / "puntuale".
  static String delay(Duration value) {
    final minutes = value.inMinutes;
    if (minutes == 0) return 'puntuale';
    return minutes > 0 ? '+$minutes min' : '$minutes min';
  }

  static String integer(int value) => _number.format(value);

  /// Quantità con il nome concordato: "1 servizio", "3 servizi".
  static String count(int value, String singular, String plural) =>
      '${integer(value)} ${value == 1 ? singular : plural}';

  static String decimal(double value) => _oneDecimal.format(value);

  static String percent(double? ratio) =>
      ratio == null ? '—' : '${(ratio * 100).round()}%';

  static String fileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${_oneDecimal.format(bytes / (1024 * 1024))} MB';
  }

  /// Tempo relativo: "adesso", "5 min fa", "tra 20 min", "ieri 14:20".
  static String relative(DateTime value, DateTime now) {
    final diff = now.difference(value);
    final future = diff.isNegative;
    final minutes = diff.inMinutes.abs();
    if (minutes < 1) return 'adesso';
    if (minutes < 60) return future ? 'tra $minutes min' : '$minutes min fa';
    final hours = diff.inHours.abs();
    if (isSameDay(value, now) && hours < 12) {
      return future ? 'tra $hours h' : '$hours h fa';
    }
    final days = startOfDay(value).difference(startOfDay(now)).inDays;
    if (days == -1) return 'ieri ${time(value)}';
    if (days == 0) return 'oggi ${time(value)}';
    if (days == 1) return 'domani ${time(value)}';
    return '${dateShort(value)} ${time(value)}';
  }

  /// "Oggi", "Ieri", "Domani" oppure "gio 24 set".
  static String dayLabel(DateTime value, DateTime now) {
    final days = startOfDay(value).difference(startOfDay(now)).inDays;
    return switch (days) {
      0 => 'Oggi',
      -1 => 'Ieri',
      1 => 'Domani',
      _ => capitalize(dayMedium(value)),
    };
  }

  static String capitalize(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

  /// Minuti come orario "HH:mm" (per campi orario).
  static String minutesOfDay(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}

/// Intervallo di tempo semiaperto `[start, end)`.
///
/// Il dominio non dipende da Flutter, quindi non usa `DateTimeRange`.
class DateRange {
  DateRange(this.start, this.end)
    : assert(!end.isBefore(start), 'end deve essere >= start');

  /// Giorno di calendario locale che contiene [day] (da mezzanotte a mezzanotte).
  factory DateRange.day(DateTime day) {
    final start = startOfDay(day);
    return DateRange(start, addDays(start, 1));
  }

  /// Settimana (lunedì-domenica) che contiene [day].
  factory DateRange.week(DateTime day) {
    final start = startOfWeek(day);
    return DateRange(start, addDays(start, 7));
  }

  /// Mese di calendario che contiene [day].
  factory DateRange.month(DateTime day) => DateRange(
    DateTime(day.year, day.month),
    DateTime(day.year, day.month + 1),
  );

  /// Da [first] a [last] compresi, a giorni interi.
  factory DateRange.days(DateTime first, DateTime last) =>
      DateRange(startOfDay(first), addDays(startOfDay(last), 1));

  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);

  bool contains(DateTime instant) =>
      !instant.isBefore(start) && instant.isBefore(end);

  bool overlaps(DateRange other) =>
      start.isBefore(other.end) && other.start.isBefore(end);

  /// Intersezione, o `null` se gli intervalli non si sovrappongono.
  DateRange? intersection(DateRange other) {
    if (!overlaps(other)) return null;
    final s = start.isAfter(other.start) ? start : other.start;
    final e = end.isBefore(other.end) ? end : other.end;
    return DateRange(s, e);
  }

  /// Giorni di calendario toccati dall'intervallo.
  List<DateTime> get days {
    final result = <DateTime>[];
    var day = startOfDay(start);
    while (day.isBefore(end)) {
      result.add(day);
      day = addDays(day, 1);
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DateRange($start - $end)';
}

/// Mezzanotte (ora locale) del giorno che contiene [value].
DateTime startOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Lunedì della settimana che contiene [value].
DateTime startOfWeek(DateTime value) {
  final day = startOfDay(value);
  return addDays(day, -(day.weekday - DateTime.monday));
}

/// Aggiunge giorni di calendario senza errori al cambio dell'ora legale.
DateTime addDays(DateTime value, int days) => DateTime(
  value.year,
  value.month,
  value.day + days,
  value.hour,
  value.minute,
  value.second,
  value.millisecond,
);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Data odierna alle [hour]:[minute].
DateTime atTime(DateTime day, int hour, int minute) =>
    DateTime(day.year, day.month, day.day, hour, minute);

/// Minuti trascorsi dalla mezzanotte del giorno di [value].
int minutesSinceMidnight(DateTime value) => value.hour * 60 + value.minute;

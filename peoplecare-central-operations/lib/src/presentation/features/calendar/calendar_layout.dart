/// Disposizione su corsie di elementi che si sovrappongono nel tempo.
///
/// Logica pura (senza Flutter), usata dalla vista giorno del calendario e
/// verificata dai test.
class LanePlacement<T> {
  const LanePlacement(this.item, this.lane);

  final T item;
  final int lane;
}

class LaneLayout<T> {
  const LaneLayout(this.placements, this.laneCount);

  final List<LanePlacement<T>> placements;

  /// Numero di corsie usate (almeno 1).
  final int laneCount;
}

/// Assegna a ogni elemento la prima corsia libera, in ordine di inizio.
LaneLayout<T> assignLanes<T>(
  Iterable<T> items, {
  required DateTime Function(T item) start,
  required DateTime Function(T item) end,
}) {
  final sorted = items.toList()
    ..sort((a, b) {
      final byStart = start(a).compareTo(start(b));
      return byStart != 0 ? byStart : end(b).compareTo(end(a));
    });
  final laneEnds = <DateTime>[];
  final placements = <LanePlacement<T>>[];
  for (final item in sorted) {
    final s = start(item);
    var e = end(item);
    if (!e.isAfter(s)) e = s.add(const Duration(minutes: 1));
    var lane = laneEnds.indexWhere((laneEnd) => !laneEnd.isAfter(s));
    if (lane < 0) {
      lane = laneEnds.length;
      laneEnds.add(e);
    } else {
      laneEnds[lane] = e;
    }
    placements.add(LanePlacement(item, lane));
  }
  return LaneLayout(placements, laneEnds.isEmpty ? 1 : laneEnds.length);
}

/// Arrotonda i minuti al passo indicato (es. 15).
int snapMinutes(double minutes, {int step = 15}) =>
    (minutes / step).round() * step;

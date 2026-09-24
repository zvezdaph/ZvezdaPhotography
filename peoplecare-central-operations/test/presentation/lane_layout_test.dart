import 'package:flutter_test/flutter_test.dart';
import 'package:peoplecare_central_operations/src/presentation/features/calendar/calendar_layout.dart';

void main() {
  final day = DateTime(2026, 9, 24);
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(day.year, day.month, day.day, hour, minute);

  LaneLayout<(String, DateTime, DateTime)> layout(
    List<(String, DateTime, DateTime)> items,
  ) => assignLanes(items, start: (i) => i.$2, end: (i) => i.$3);

  Map<String, int> lanes(LaneLayout<(String, DateTime, DateTime)> result) => {
    for (final p in result.placements) p.item.$1: p.lane,
  };

  test('servizi senza sovrapposizioni restano su una corsia', () {
    final result = layout([
      ('a', at(8), at(9)),
      ('b', at(9), at(10)),
      ('c', at(11), at(12)),
    ]);
    expect(result.laneCount, 1);
    expect(lanes(result).values.toSet(), {0});
  });

  test('le sovrapposizioni aprono nuove corsie e le riusano', () {
    final result = layout([
      ('a', at(8), at(10)),
      ('b', at(9), at(11)),
      ('c', at(9, 30), at(10, 30)),
      ('d', at(10), at(12)),
      ('e', at(11), at(12)),
    ]);
    expect(result.laneCount, 3);
    expect(lanes(result), {'a': 0, 'b': 1, 'c': 2, 'd': 0, 'e': 1});
  });

  test(
    'durata nulla occupa comunque un minuto; nessun elemento = 1 corsia',
    () {
      final result = layout([('a', at(8), at(8)), ('b', at(8), at(9))]);
      expect(result.laneCount, 2);
      expect(layout(const []).laneCount, 1);
    },
  );

  test('aggancio dei minuti al passo', () {
    expect(snapMinutes(7), 0);
    expect(snapMinutes(8), 15);
    expect(snapMinutes(52), 45);
    expect(snapMinutes(53, step: 5), 55);
  });
}

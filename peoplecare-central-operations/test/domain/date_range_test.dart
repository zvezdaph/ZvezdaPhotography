import 'package:flutter_test/flutter_test.dart';
import 'package:peoplecare_central_operations/src/domain/domain.dart';

void main() {
  group('DateRange', () {
    test('day, week e month coprono il periodo di calendario', () {
      final instant = DateTime(2026, 9, 24, 15, 40);
      expect(
        DateRange.day(instant),
        DateRange(DateTime(2026, 9, 24), DateTime(2026, 9, 25)),
      );
      // Settimana da lunedì 21 a domenica 27 settembre.
      expect(
        DateRange.week(instant),
        DateRange(DateTime(2026, 9, 21), DateTime(2026, 9, 28)),
      );
      expect(
        DateRange.month(instant),
        DateRange(DateTime(2026, 9), DateTime(2026, 10)),
      );
      expect(
        DateRange.days(DateTime(2026, 9, 1, 12), DateTime(2026, 9, 3, 8)),
        DateRange(DateTime(2026, 9), DateTime(2026, 9, 4)),
      );
    });

    test('è semiaperto: la fine non è inclusa', () {
      final range = DateRange(
        DateTime(2026, 9, 24, 8),
        DateTime(2026, 9, 24, 9),
      );
      expect(range.contains(DateTime(2026, 9, 24, 8)), isTrue);
      expect(range.contains(DateTime(2026, 9, 24, 8, 59)), isTrue);
      expect(range.contains(DateTime(2026, 9, 24, 9)), isFalse);
    });

    test('sovrapposizione e intersezione', () {
      final a = DateRange(DateTime(2026, 9, 24, 8), DateTime(2026, 9, 24, 10));
      final b = DateRange(DateTime(2026, 9, 24, 9), DateTime(2026, 9, 24, 11));
      final c = DateRange(DateTime(2026, 9, 24, 10), DateTime(2026, 9, 24, 12));
      expect(a.overlaps(b), isTrue);
      expect(
        a.intersection(b),
        DateRange(DateTime(2026, 9, 24, 9), DateTime(2026, 9, 24, 10)),
      );
      // Intervalli adiacenti non si sovrappongono.
      expect(a.overlaps(c), isFalse);
      expect(a.intersection(c), isNull);
    });

    test('days elenca i giorni toccati', () {
      final range = DateRange(
        DateTime(2026, 9, 23, 22),
        DateTime(2026, 9, 25, 1),
      );
      expect(range.days, [
        DateTime(2026, 9, 23),
        DateTime(2026, 9, 24),
        DateTime(2026, 9, 25),
      ]);
    });

    test('addDays mantiene l\'ora anche al cambio dell\'ora legale', () {
      // In Italia l'ora legale termina domenica 25 ottobre 2026.
      final before = DateTime(2026, 10, 24, 9, 30);
      final after = addDays(before, 2);
      expect(after.day, 26);
      expect(after.hour, 9);
      expect(after.minute, 30);
      expect(startOfWeek(DateTime(2026, 9, 27)), DateTime(2026, 9, 21));
      expect(minutesSinceMidnight(DateTime(2026, 9, 24, 7, 45)), 465);
    });
  });
}

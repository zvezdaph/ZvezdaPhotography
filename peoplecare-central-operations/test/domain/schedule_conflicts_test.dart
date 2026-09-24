import 'package:flutter_test/flutter_test.dart';
import 'package:peoplecare_central_operations/src/domain/domain.dart';

import '../support/test_support.dart';

void main() {
  const detector = ScheduleConflictDetector();
  final day = DateTime(2026, 9, 25);
  final now = DateTime(2026, 9, 25, 7);

  DateTime at(int hour, [int minute = 0]) => atTime(day, hour, minute);

  test('rileva i servizi sovrapposti dello stesso operatore', () {
    final a = buildService(
      id: 'a',
      start: at(9),
      duration: const Duration(minutes: 90),
    );
    final b = buildService(id: 'b', start: at(10));
    final c = buildService(id: 'c', start: at(11));
    final conflicts = detector.detect([a, b, c], now: now);
    expect(conflicts, hasLength(1));
    expect(conflicts.single.involves('a'), isTrue);
    expect(conflicts.single.involves('b'), isTrue);
    expect(conflicts.single.overlap.duration, const Duration(minutes: 30));
    expect(conflicts.single.other('a').id, 'b');
  });

  test('ignora operatori diversi, servizi non assegnati e annullati', () {
    final services = [
      buildService(id: 'a', start: at(9)),
      buildService(id: 'b', start: at(9), operatorId: 'op-2'),
      buildService(
        id: 'c',
        start: at(9),
        operatorId: null,
        status: ServiceStatus.daAssegnare,
      ),
      buildService(id: 'd', start: at(9), status: ServiceStatus.annullato),
      buildService(
        id: 'e',
        start: at(9),
        status: ServiceStatus.daRiprogrammare,
      ),
    ];
    expect(detector.detect(services, now: now), isEmpty);
  });

  test(
    'un servizio in corso oltre la fine occupa l\'operatore fino ad adesso',
    () {
      final running = buildService(
        id: 'running',
        start: at(8),
        status: ServiceStatus.inCorso,
        actualStart: at(8),
      );
      final next = buildService(id: 'next', start: at(9, 15));
      expect(detector.detect([running, next], now: at(9, 0)), isEmpty);
      expect(detector.detect([running, next], now: at(9, 30)), hasLength(1));
    },
  );

  test('overlapsForSlot esclude il servizio che si sta spostando', () {
    final a = buildService(id: 'a', start: at(9));
    final b = buildService(id: 'b', start: at(10));
    final slot = DateRange(at(9, 30), at(10, 30));
    expect(
      detector
          .overlapsForSlot(
            operatorId: 'op-1',
            slot: slot,
            services: [a, b],
            now: now,
          )
          .map((s) => s.id),
      ['a', 'b'],
    );
    expect(
      detector
          .overlapsForSlot(
            operatorId: 'op-1',
            slot: slot,
            services: [a, b],
            excludeServiceId: 'a',
            now: now,
          )
          .map((s) => s.id),
      ['b'],
    );
  });

  test('detectByService indicizza entrambi i servizi del conflitto', () {
    final a = buildService(id: 'a', start: at(9));
    final b = buildService(id: 'b', start: at(9, 30));
    final byService = detector.detectByService([a, b], now: now);
    expect(byService.keys, containsAll(['a', 'b']));
  });
}

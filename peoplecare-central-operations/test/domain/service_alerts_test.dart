import 'package:flutter_test/flutter_test.dart';
import 'package:peoplecare_central_operations/src/domain/domain.dart';

import '../support/test_support.dart';

void main() {
  const evaluator = ServiceAlertEvaluator();
  final now = DateTime(2026, 9, 24, 10, 0);

  List<ServiceAlertKind> kinds(
    Iterable<Service> services, {
    Map<String, Operator> operators = const {},
  }) => evaluator
      .evaluate(services, now: now, operatorsById: operators)
      .map((a) => a.kind)
      .toList();

  test('avvio in ritardo: attenzione oltre 10 minuti, critico oltre 30', () {
    final slightly = buildService(
      id: 'a',
      start: now.subtract(const Duration(minutes: 15)),
    );
    final very = buildService(
      id: 'b',
      operatorId: 'op-2',
      start: now.subtract(const Duration(minutes: 45)),
    );
    final alerts = evaluator.evaluate([slightly, very], now: now);
    expect(alerts.map((a) => a.kind).toSet(), {
      ServiceAlertKind.avvioInRitardo,
    });
    // Le critiche vengono prima.
    expect(alerts.first.service.id, 'b');
    expect(alerts.first.level, AlertLevel.critico);
    expect(alerts.last.level, AlertLevel.attenzione);
    expect(alerts.last.delay, const Duration(minutes: 15));
  });

  test('entro la tolleranza nessuna anomalia', () {
    expect(
      kinds([buildService(start: now.subtract(const Duration(minutes: 5)))]),
      isEmpty,
    );
  });

  test(
    'sforamento, da assegnare imminente, da riprogrammare, non eseguito',
    () {
      final overrun = buildService(
        id: 'overrun',
        start: now.subtract(const Duration(hours: 2)),
        status: ServiceStatus.inCorso,
        actualStart: now.subtract(const Duration(hours: 2)),
      );
      final imminent = buildService(
        id: 'imminent',
        operatorId: null,
        status: ServiceStatus.daAssegnare,
        start: now.add(const Duration(hours: 1)),
      );
      final toReschedule = buildService(
        id: 'resched',
        operatorId: 'op-3',
        status: ServiceStatus.daRiprogrammare,
        start: now.add(const Duration(days: 1)),
      );
      final notExecuted = buildService(
        id: 'ne',
        operatorId: 'op-4',
        status: ServiceStatus.nonEseguito,
        start: now.subtract(const Duration(hours: 3)),
      );
      final alerts = evaluator.evaluate([
        overrun,
        imminent,
        toReschedule,
        notExecuted,
      ], now: now);
      expect(
        alerts.map((a) => a.kind),
        containsAll([
          ServiceAlertKind.sforamento,
          ServiceAlertKind.daAssegnareImminente,
          ServiceAlertKind.daRiprogrammare,
          ServiceAlertKind.nonEseguito,
        ]),
      );
      expect(
        alerts
            .firstWhere((a) => a.kind == ServiceAlertKind.daAssegnareImminente)
            .level,
        AlertLevel.critico,
      );
    },
  );

  test('operatore non attivo e richieste di modifica aperte', () {
    final service = buildService(
      start: now.add(const Duration(hours: 5)),
      openChangeRequestCount: 1,
    );
    final suspended = buildOperator(status: OperatorStatus.sospeso);
    expect(
      kinds([service], operators: {'op-1': suspended}),
      containsAll([
        ServiceAlertKind.operatoreNonAttivo,
        ServiceAlertKind.richiestaModificaAperta,
      ]),
    );
  });

  test('sovrapposizione critica, ignorata se entrambi completati', () {
    final start = now.add(const Duration(hours: 2));
    final a = buildService(id: 'a', start: start);
    final b = buildService(
      id: 'b',
      start: start.add(const Duration(minutes: 30)),
    );
    expect(kinds([a, b]), [ServiceAlertKind.sovrapposizione]);

    final past = now.subtract(const Duration(hours: 4));
    final doneA = buildService(
      id: 'c',
      start: past,
      status: ServiceStatus.completato,
      actualStart: past,
      actualEnd: past.add(const Duration(hours: 1)),
    );
    final doneB = buildService(
      id: 'd',
      start: past.add(const Duration(minutes: 30)),
      status: ServiceStatus.completato,
      actualStart: past.add(const Duration(minutes: 30)),
      actualEnd: past.add(const Duration(minutes: 90)),
    );
    expect(kinds([doneA, doneB]), isEmpty);
  });
}

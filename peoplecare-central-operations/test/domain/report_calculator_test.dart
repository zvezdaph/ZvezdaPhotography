import 'package:flutter_test/flutter_test.dart';
import 'package:peoplecare_central_operations/src/domain/domain.dart';

import '../support/test_support.dart';

void main() {
  test('aggrega stati, puntualità, minuti e righe per dimensione', () {
    final day = DateTime(2026, 9, 21);
    final period = DateRange.days(day, DateTime(2026, 9, 22));
    DateTime at(int dayOffset, int hour, [int minute = 0]) =>
        addDays(atTime(day, hour, minute), dayOffset);

    final services = [
      // Puntuale (+5), 60 minuti effettivi.
      buildService(
        id: 's1',
        start: at(0, 8),
        status: ServiceStatus.completato,
        actualStart: at(0, 8, 5),
        actualEnd: at(0, 9, 5),
      ),
      // In ritardo (+25), 30 minuti effettivi, operatore diverso.
      buildService(
        id: 's2',
        operatorId: 'op-2',
        start: at(0, 10),
        status: ServiceStatus.completato,
        actualStart: at(0, 10, 25),
        actualEnd: at(0, 10, 55),
      ),
      buildService(
        id: 's3',
        start: at(1, 9),
        status: ServiceStatus.nonEseguito,
        facilityId: 'str-2',
      ),
      buildService(
        id: 's4',
        start: at(1, 11),
        status: ServiceStatus.annullato,
        kind: const CustomServiceKind('Consegna ausili'),
      ),
      // Fuori periodo: ignorato.
      buildService(id: 's5', start: at(3, 9), status: ServiceStatus.completato),
    ];
    final report = const ReportCalculator().compute(
      query: ReportQuery(period: period),
      services: services,
      changeRequests: [
        ChangeRequest(
          id: 'rm-1',
          code: 'RM-000001',
          serviceId: 's1',
          serviceCode: 'SRV-1',
          operatorId: 'op-1',
          operatorName: 'Anna Rossi',
          reason: ChangeRequestReason.problemaOrario,
          message: 'Posso anticipare?',
          status: ChangeRequestStatus.chiusa,
          createdAt: at(0, 7),
          updatedAt: at(0, 7),
        ),
      ],
      operatorsById: {
        'op-1': buildOperator(),
        'op-2': buildOperator(id: 'op-2', firstName: 'Luca', lastName: 'Verdi'),
      },
      facilitiesById: const {},
      generatedAt: at(2, 8),
    );

    expect(report.totalServices, 4);
    expect(report.count(ServiceStatus.completato), 2);
    expect(report.count(ServiceStatus.nonEseguito), 1);
    expect(report.count(ServiceStatus.annullato), 1);
    expect(report.startedServices, 2);
    expect(report.onTimeStarts, 1);
    expect(report.punctualityRate, 0.5);
    expect(report.averageStartDelayMinutes, 15);
    expect(report.deliveredMinutes, 90);
    // Annullati esclusi dai minuti programmati.
    expect(report.scheduledMinutes, 180);
    expect(report.completionRate, closeTo(2 / 3, 1e-9));
    expect(report.changeRequestCount, 1);
    expect(
      report.changeRequestsByReason[ChangeRequestReason.problemaOrario],
      1,
    );
    expect(report.daily, hasLength(2));
    expect(report.daily.first.total, 2);
    expect(report.operators.first.operatorName, 'Anna Rossi');
    expect(
      report.serviceTypes.map((row) => row.label),
      containsAll(['Igiene personale', 'Servizi personalizzati']),
    );
    expect(
      report.serviceTypes
          .firstWhere((row) => row.serviceTypeId == null)
          .totalServices,
      1,
    );
    expect(report.facilities.map((row) => row.facilityId), ['str-1', 'str-2']);
  });

  test('filtra per struttura e gestisce il periodo vuoto', () {
    final period = DateRange.day(DateTime(2026, 9, 21));
    final report = const ReportCalculator().compute(
      query: ReportQuery(period: period, facilityId: 'str-9'),
      services: [buildService(start: DateTime(2026, 9, 21, 9))],
      changeRequests: const [],
      operatorsById: const {},
      facilitiesById: const {},
      generatedAt: DateTime(2026, 9, 22),
    );
    expect(report.totalServices, 0);
    expect(report.completionRate, isNull);
    expect(report.punctualityRate, isNull);
    expect(report.averageStartDelayMinutes, isNull);
  });
}

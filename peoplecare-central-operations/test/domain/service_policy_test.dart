import 'package:flutter_test/flutter_test.dart';
import 'package:peoplecare_central_operations/src/domain/domain.dart';

import '../support/test_support.dart';

void main() {
  final start = DateTime(2026, 9, 25, 9);

  Service withStatus(
    ServiceStatus status, {
    String? operatorId = 'op-1',
    DateTime? actualStart,
    int documentCount = 0,
    int openChangeRequestCount = 0,
  }) => buildService(
    start: start,
    status: status,
    operatorId: operatorId,
    actualStart: actualStart,
    documentCount: documentCount,
    openChangeRequestCount: openChangeRequestCount,
  );

  group('ServicePolicy', () {
    test('solo i servizi da pianificare sono modificabili', () {
      const plannable = {
        ServiceStatus.daAssegnare,
        ServiceStatus.assegnato,
        ServiceStatus.daRiprogrammare,
      };
      for (final status in ServiceStatus.values) {
        final service = withStatus(status);
        final expected = plannable.contains(status);
        expect(ServicePolicy.canEdit(service), expected, reason: status.code);
        expect(ServicePolicy.canReschedule(service), expected);
        expect(ServicePolicy.canReassign(service), expected);
        expect(ServicePolicy.canCancel(service), expected);
        expect(ServicePolicy.canAddDocuments(service), isTrue);
      }
      expect(
        ServicePolicy.canMarkToReschedule(withStatus(ServiceStatus.assegnato)),
        isTrue,
      );
      expect(
        ServicePolicy.canMarkToReschedule(
          withStatus(ServiceStatus.daRiprogrammare),
        ),
        isFalse,
      );
    });

    test('eliminazione solo per servizi mai avviati, senza operatore, '
        'documenti o richieste aperte', () {
      expect(
        ServicePolicy.canDelete(
          withStatus(ServiceStatus.daAssegnare, operatorId: null),
        ),
        isTrue,
      );
      expect(
        ServicePolicy.canDelete(withStatus(ServiceStatus.annullato)),
        isTrue,
      );
      for (final blocked in [
        withStatus(ServiceStatus.assegnato),
        withStatus(ServiceStatus.inCorso, actualStart: start),
        withStatus(ServiceStatus.completato, actualStart: start),
        withStatus(ServiceStatus.nonEseguito),
        withStatus(ServiceStatus.daRiprogrammare),
        withStatus(
          ServiceStatus.daAssegnare,
          operatorId: null,
          documentCount: 1,
        ),
        withStatus(
          ServiceStatus.daAssegnare,
          operatorId: null,
          openChangeRequestCount: 1,
        ),
      ]) {
        expect(
          ServicePolicy.deleteBlockedReason(blocked),
          isNotNull,
          reason: blocked.status.code,
        );
      }
    });

    test('orario: fine dopo l\'inizio e durata massima 12 ore', () {
      expect(ServicePolicy.validateSchedule(start, start), isNotNull);
      expect(
        ServicePolicy.validateSchedule(
          start,
          start.subtract(const Duration(minutes: 5)),
        ),
        isNotNull,
      );
      expect(
        ServicePolicy.validateSchedule(
          start,
          start.add(const Duration(hours: 12, minutes: 1)),
        ),
        isNotNull,
      );
      expect(
        ServicePolicy.validateSchedule(
          start,
          start.add(const Duration(hours: 12)),
        ),
        isNull,
      );
    });

    test('stato dopo riprogrammazione, riassegnazione e modifica', () {
      expect(
        ServicePolicy.statusAfterReschedule(operatorId: null),
        ServiceStatus.daAssegnare,
      );
      expect(
        ServicePolicy.statusAfterReschedule(operatorId: 'op-1'),
        ServiceStatus.assegnato,
      );
      expect(
        ServicePolicy.statusAfterReassign(
          current: ServiceStatus.daRiprogrammare,
          operatorId: 'op-2',
        ),
        ServiceStatus.daRiprogrammare,
      );
      expect(
        ServicePolicy.statusAfterReassign(
          current: ServiceStatus.assegnato,
          operatorId: null,
        ),
        ServiceStatus.daAssegnare,
      );
      expect(
        ServicePolicy.statusAfterUpdate(
          current: ServiceStatus.daRiprogrammare,
          operatorId: 'op-1',
          scheduleChanged: false,
        ),
        ServiceStatus.daRiprogrammare,
      );
      expect(
        ServicePolicy.statusAfterUpdate(
          current: ServiceStatus.daRiprogrammare,
          operatorId: 'op-1',
          scheduleChanged: true,
        ),
        ServiceStatus.assegnato,
      );
    });
  });

  group('Service', () {
    test('intervallo occupato con gli orari reali', () {
      final now = DateTime(2026, 9, 25, 10, 30);
      final inProgress = buildService(
        start: start,
        status: ServiceStatus.inCorso,
        actualStart: start.add(const Duration(minutes: 5)),
      );
      // In corso oltre la fine programmata: occupa fino ad adesso.
      expect(
        inProgress.occupiedRange(now),
        DateRange(start.add(const Duration(minutes: 5)), now),
      );
      final completed = buildService(
        start: start,
        status: ServiceStatus.completato,
        actualStart: start.add(const Duration(minutes: 10)),
        actualEnd: start.add(const Duration(minutes: 55)),
      );
      expect(completed.occupiedRange(now).duration.inMinutes, 45);
      expect(completed.startDelay, const Duration(minutes: 10));
      expect(completed.actualDuration, const Duration(minutes: 45));
    });

    test('codici di stato e priorità condivisi con il sistema', () {
      expect(ServiceStatus.values.map((s) => s.code), [
        'da_assegnare',
        'assegnato',
        'in_corso',
        'completato',
        'annullato',
        'non_eseguito',
        'da_riprogrammare',
      ]);
      for (final status in ServiceStatus.values) {
        expect(ServiceStatus.fromCode(status.code), status);
      }
      expect(ServicePriority.values.map((p) => p.code), [
        'bassa',
        'normale',
        'alta',
        'urgente',
      ]);
    });
  });
}

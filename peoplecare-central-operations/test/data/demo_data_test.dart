import 'package:flutter_test/flutter_test.dart';
import 'package:peoplecare_central_operations/src/domain/domain.dart';

import '../support/test_support.dart';

/// Coerenza dei dati DEMO generati attorno a [testNow].
void main() {
  final backend = createSeededBackend();
  final services = backend.services.values.toList();
  final operators = backend.operators.values.toList();

  test('più strutture e operatori con codice OP-000000 univoco', () {
    expect(backend.facilities.length, greaterThanOrEqualTo(2));
    final codes = operators.map((o) => o.code).toList();
    expect(codes.toSet(), hasLength(codes.length));
    for (final code in codes) {
      expect(code, matches(RegExp(r'^OP-\d{6}$')));
    }
    // Il modello a più strutture è già usato dai dati demo.
    expect(operators.any((o) => o.secondaryFacilityIds.isNotEmpty), isTrue);
    for (final operator in operators) {
      expect(backend.facilities, contains(operator.primaryFacilityId));
      expect(
        operator.secondaryFacilityIds,
        isNot(contains(operator.primaryFacilityId)),
      );
    }
    expect(
      operators.map((o) => o.status).toSet(),
      containsAll(OperatorStatus.values),
    );
  });

  test('tutti gli stati del servizio sono rappresentati', () {
    expect(
      services.map((s) => s.status).toSet(),
      containsAll(ServiceStatus.values),
    );
    final today = DateRange.day(testNow);
    final todays = services.where((s) => today.contains(s.scheduledStart));
    expect(todays.where((s) => s.status == ServiceStatus.inCorso), isNotEmpty);
    expect(
      todays.where((s) => s.status == ServiceStatus.completato),
      isNotEmpty,
    );
  });

  test('orari reali coerenti con lo stato', () {
    for (final s in services) {
      expect(s.scheduledEnd.isAfter(s.scheduledStart), isTrue, reason: s.code);
      switch (s.status) {
        case ServiceStatus.inCorso:
          expect(s.actualStart, isNotNull, reason: s.code);
          expect(s.actualEnd, isNull, reason: s.code);
          expect(s.actualStart!.isAfter(testNow), isFalse, reason: s.code);
        case ServiceStatus.completato:
          expect(s.actualStart, isNotNull, reason: s.code);
          expect(s.actualEnd, isNotNull, reason: s.code);
          expect(s.actualEnd!.isAfter(s.actualStart!), isTrue, reason: s.code);
          expect(s.actualEnd!.isAfter(testNow), isFalse, reason: s.code);
        case ServiceStatus.daAssegnare:
          expect(s.operatorId, isNull, reason: s.code);
          expect(s.actualStart, isNull, reason: s.code);
        case ServiceStatus.assegnato:
          expect(s.operatorId, isNotNull, reason: s.code);
          expect(s.actualStart, isNull, reason: s.code);
        default:
          break;
      }
    }
  });

  test('i contatori derivati corrispondono a documenti e richieste', () {
    for (final s in services) {
      final documents = backend.documents.values.where(
        (d) => d.owner.type == DocumentOwnerType.servizio && d.owner.id == s.id,
      );
      final openRequests = backend.changeRequests.values.where(
        (r) => r.serviceId == s.id && r.status.isOpen,
      );
      expect(s.documentCount, documents.length, reason: s.code);
      expect(s.openChangeRequestCount, openRequests.length, reason: s.code);
    }
  });

  test('richieste di modifica in ogni stato, con motivi diversi', () {
    final requests = backend.changeRequests.values;
    expect(
      requests.map((r) => r.status).toSet(),
      containsAll(ChangeRequestStatus.values),
    );
    expect(requests.map((r) => r.reason).toSet().length, greaterThan(3));
    for (final r in requests) {
      expect(backend.services, contains(r.serviceId));
      expect(r.code, matches(RegExp(r'^RM-\d{6}$')));
      if (r.status == ChangeRequestStatus.chiusa) {
        expect(r.outcome, isNotNull, reason: r.code);
      }
    }
  });

  test('documenti per ogni tipo di proprietario e notifiche di ogni tipo', () {
    expect(
      backend.documents.values.map((d) => d.owner.type).toSet(),
      containsAll(DocumentOwnerType.values),
    );
    expect(backend.documents.values.any((d) => d.isPendingReview), isTrue);
    expect(
      backend.notifications.map((n) => n.type).toSet(),
      containsAll(NotificationType.values),
    );
  });

  test(
    'dati fittizi: email su dominio riservato e telefoni con blocco 000',
    () {
      for (final operator in operators) {
        expect(operator.email, endsWith('.example'), reason: operator.code);
        expect(operator.phone, contains('000'), reason: operator.code);
      }
    },
  );

  test('stesso orologio e stesso seme producono gli stessi dati', () {
    final again = createSeededBackend();
    expect(again.services.length, backend.services.length);
    expect(
      again.services.values.map((s) => '${s.code}|${s.status.code}').toList(),
      backend.services.values.map((s) => '${s.code}|${s.status.code}').toList(),
    );
  });
}

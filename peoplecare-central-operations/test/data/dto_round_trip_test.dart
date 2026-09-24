import 'package:flutter_test/flutter_test.dart';
import 'package:peoplecare_central_operations/src/data/dto/entity_json.dart';
import 'package:peoplecare_central_operations/src/data/dto/json_reader.dart';
import 'package:peoplecare_central_operations/src/data/dto/query_params.dart';
import 'package:peoplecare_central_operations/src/domain/domain.dart';

import '../support/test_support.dart';

/// Tutte le entità dei dati demo sopravvivono a scrittura e rilettura JSON.
void main() {
  final backend = createSeededBackend();

  void roundTrip<T>(
    Iterable<T> items,
    JsonMap Function(T item) encode,
    T Function(JsonMap json) decode,
  ) {
    expect(items, isNotEmpty);
    for (final item in items) {
      final json = encode(item);
      expect(encode(decode(json)), json);
    }
  }

  test('servizi, operatori, strutture, tipologie, pazienti', () {
    roundTrip(backend.services.values, serviceToJson, serviceFromJson);
    roundTrip(backend.operators.values, operatorToJson, operatorFromJson);
    roundTrip(backend.facilities.values, facilityToJson, facilityFromJson);
    roundTrip(
      backend.serviceTypes.values,
      serviceTypeToJson,
      serviceTypeFromJson,
    );
    roundTrip(backend.patients.values, patientToJson, patientFromJson);
  });

  test('richieste, documenti, notifiche, registro attività', () {
    roundTrip(
      backend.changeRequests.values,
      changeRequestToJson,
      changeRequestFromJson,
    );
    roundTrip(backend.documents.values, documentToJson, documentFromJson);
    roundTrip(backend.notifications, notificationToJson, notificationFromJson);
    roundTrip(backend.auditLog, auditEntryToJson, auditEntryFromJson);
  });

  test('report operativo', () async {
    final repos = createTestRepositories();
    final report = await repos.reports.getOperationalReport(
      ReportQuery(period: DateRange.week(testNow)),
    );
    final json = operationalReportToJson(report);
    expect(operationalReportToJson(operationalReportFromJson(json)), json);
    await repos.dispose();
  });

  test('timestamp RFC 3339 in UTC', () {
    final value = DateTime.utc(2026, 9, 24, 7, 30).toLocal();
    expect(formatTimestamp(value), '2026-09-24T07:30:00Z');
    expect(
      formatTimestamp(DateTime.utc(2026, 9, 24, 7, 30, 5, 120)),
      '2026-09-24T07:30:05.120Z',
    );
    expect(parseTimestamp('2026-09-24T09:30:00+02:00'), value);
    expect(formatDate(DateTime(2026, 1, 5)), '2026-01-05');
  });

  test('parametri di ricerca dei servizi', () {
    final range = DateRange(
      DateTime.utc(2026, 9, 21).toLocal(),
      DateTime.utc(2026, 9, 28).toLocal(),
    );
    final params = serviceQueryParams(
      ServiceQuery(
        range: range,
        facilityIds: const {'str-2', 'str-1'},
        operator: const AssignedTo('opr-000184'),
        statuses: const {ServiceStatus.assegnato, ServiceStatus.inCorso},
        priorities: const {ServicePriority.urgente},
        search: 'ravasio',
        sort: ServiceSort.priority,
        descending: true,
      ),
      const PageRequest(page: 2, pageSize: 25),
    );
    expect(params, {
      'from': '2026-09-21T00:00:00Z',
      'to': '2026-09-28T00:00:00Z',
      'facility_id': 'str-1,str-2',
      'operator_id': 'opr-000184',
      'status': 'assegnato,in_corso',
      'priority': 'urgente',
      'q': 'ravasio',
      'sort': 'priority',
      'order': 'desc',
      'page': '2',
      'page_size': '25',
    });
    expect(
      serviceQueryParams(
        const ServiceQuery(operator: Unassigned(), customTypeOnly: true),
        const PageRequest(),
      ),
      containsPair('unassigned', 'true'),
    );
    expect(
      documentQueryParams(
        const DocumentQuery(
          ownerType: DocumentOwnerType.servizio,
          ownerId: 'srv-1',
          pendingReviewOnly: true,
        ),
        const PageRequest(),
      ),
      {
        'owner_type': 'servizio',
        'owner_id': 'srv-1',
        'pending_review': 'true',
        'page': '1',
        'page_size': '50',
      },
    );
  });
}

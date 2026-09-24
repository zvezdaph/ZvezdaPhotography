import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peoplecare_central_operations/src/data/dto/api_errors.dart';
import 'package:peoplecare_central_operations/src/data/dto/entity_json.dart';
import 'package:peoplecare_central_operations/src/data/dto/json_reader.dart';
import 'package:peoplecare_central_operations/src/data/dto/live_stream.dart';
import 'package:peoplecare_central_operations/src/data/dto/request_bodies.dart';
import 'package:peoplecare_central_operations/src/domain/domain.dart';

/// Gli esempi di API_CONTRACT.md sono i file in `test/fixtures/api`: questi
/// test verificano che i codec JSON li leggano e li riproducano esattamente,
/// e che il documento riporti gli stessi esempi.
const fixturesDir = 'test/fixtures/api';

Object? fixture(String name) =>
    jsonDecode(File('$fixturesDir/$name').readAsStringSync());

JsonMap fixtureMap(String name) =>
    (fixture(name)! as Map).cast<String, Object?>();

/// Rimuove ricorsivamente le chiavi nulle.
Object? stripNulls(Object? value) => switch (value) {
  Map() => {
    for (final entry in value.entries)
      if (entry.value != null) entry.key: stripNulls(entry.value),
  },
  List() => [for (final item in value) stripNulls(item)],
  _ => value,
};

void main() {
  group('risposte: lettura e scrittura identiche all\'esempio', () {
    final cases = <String, JsonMap Function(JsonMap json)>{
      'me.json': (j) => centralUserToJson(centralUserFromJson(j)),
      'facility.json': (j) => facilityToJson(facilityFromJson(j)),
      'service_type.json': (j) => serviceTypeToJson(serviceTypeFromJson(j)),
      'patient.json': (j) => patientToJson(patientFromJson(j)),
      'operator.json': (j) => operatorToJson(operatorFromJson(j)),
      'service.json': (j) => serviceToJson(serviceFromJson(j)),
      'service_custom.json': (j) => serviceToJson(serviceFromJson(j)),
      'change_request.json': (j) =>
          changeRequestToJson(changeRequestFromJson(j)),
      'document.json': (j) => documentToJson(documentFromJson(j)),
      'notification.json': (j) => notificationToJson(notificationFromJson(j)),
      'audit_entry.json': (j) => auditEntryToJson(auditEntryFromJson(j)),
      'operational_event.json': (j) =>
          operationalEventToJson(operationalEventFromJson(j)!),
      'operational_report.json': (j) =>
          operationalReportToJson(operationalReportFromJson(j)),
      'services_page.json': (j) {
        final page = pagedResultFromJson(j, serviceFromJson);
        return {
          'items': [for (final s in page.items) serviceToJson(s)],
          'total': page.total,
          'page': page.page,
          'page_size': page.pageSize,
        };
      },
    };
    for (final MapEntry(key: name, value: roundTrip) in cases.entries) {
      test(name, () {
        final json = fixtureMap(name);
        expect(roundTrip(json), json);
        // I campi null possono anche essere assenti.
        final compact = (stripNulls(json)! as Map).cast<String, Object?>();
        expect(stripNulls(roundTrip(compact)), compact);
      });
    }

    test('valori letti correttamente', () {
      final service = serviceFromJson(fixtureMap('service.json'));
      expect(service.status, ServiceStatus.inCorso);
      expect(service.kind, isA<CatalogServiceKind>());
      expect(service.patient.patientId, 'pz-004512');
      expect(service.actualStart, DateTime.utc(2026, 9, 24, 7, 34).toLocal());
      expect(service.startDelay, const Duration(minutes: 4));

      final custom = serviceFromJson(fixtureMap('service_custom.json'));
      expect(custom.isCustom, isTrue);
      expect(custom.patient, isA<ManualServicePatient>());
      expect(custom.operatorId, isNull);

      final operator = operatorFromJson(fixtureMap('operator.json'));
      expect(operator.code, 'OP-000184');
      expect(operator.facilityIds, ['str-000003', 'str-000001']);
      expect(operator.account?.status, AccountStatus.attivo);

      final request = changeRequestFromJson(fixtureMap('change_request.json'));
      expect(request.hasProposal, isTrue);
      expect(request.messages.single.authorKind, ActorKind.centrale);
    });

    test('campi obbligatori mancanti producono FormatException', () {
      final broken = fixtureMap('service.json')..remove('scheduled_start');
      expect(() => serviceFromJson(broken), throwsFormatException);
      final wrongType = fixtureMap('facility.json')..['version'] = 'tre';
      expect(() => facilityFromJson(wrongType), throwsFormatException);
    });

    test('stati sconosciuti sono un errore di formato', () {
      final service = fixtureMap('service.json')..['status'] = 'sospeso';
      expect(() => serviceFromJson(service), throwsFormatException);
      final priority = fixtureMap('service.json')..['priority'] = 'massima';
      expect(() => serviceFromJson(priority), throwsFormatException);
      final operator = fixtureMap('operator.json')..['status'] = 'ferie';
      expect(() => operatorFromJson(operator), throwsFormatException);
      final request = fixtureMap('change_request.json')..['status'] = 'x';
      expect(() => changeRequestFromJson(request), throwsFormatException);
    });

    test('valori di enumerazione sconosciuti non bloccano la lettura', () {
      final json = fixtureMap('notification.json')..['type'] = 'tipo_futuro';
      expect(notificationFromJson(json).type, NotificationType.operativa);
      final event = fixtureMap('operational_event.json')
        ..['topic'] = 'argomento_futuro';
      expect(operationalEventFromJson(event), isNull);
    });
  });

  group('richieste: corpo prodotto dal client', () {
    DateTime utc(int day, int hour, [int minute = 0]) =>
        DateTime.utc(2026, 9, day, hour, minute).toLocal();

    const registered = RegisteredServicePatient(
      patientId: 'pz-004512',
      firstName: 'Rosa',
      lastName: 'Ravasio',
    );
    final draft = ServiceDraft(
      kind: const CatalogServiceKind(
        serviceTypeId: 'ts-000004',
        name: 'Medicazione',
      ),
      scheduledStart: utc(25, 9),
      scheduledEnd: utc(25, 9, 30),
      patient: registered,
      facilityId: 'str-000003',
      operatorId: 'opr-000184',
      priority: ServicePriority.alta,
      address: 'Via Tasso 76, Bergamo',
      phone: '+39 035 000 4512',
      directions: 'Citofono Ravasio R., secondo piano senza ascensore.',
      notes: 'Controllare la medicazione al tallone sinistro.',
    );

    test('creazione e modifica servizio', () {
      expect(serviceDraftToJson(draft), fixture('service_create_request.json'));
      expect(
        serviceDraftToJson(draft, expectedVersion: 4),
        fixture('service_update_request.json'),
      );
      final custom = ServiceDraft(
        kind: const CustomServiceKind('Consegna ausili e verifica domicilio'),
        scheduledStart: utc(26, 12),
        scheduledEnd: utc(26, 13),
        patient: const ManualServicePatient(
          firstName: 'Giovanni',
          lastName: 'Cortinovis',
        ),
        facilityId: 'str-000001',
        address: 'Via Borgo Palazzo 74, Seriate',
      );
      expect(
        serviceDraftToJson(custom),
        fixture('service_create_custom_request.json'),
      );
    });

    test('azioni sul servizio', () {
      expect(
        rescheduleRequestToJson(
          start: utc(25, 9),
          end: utc(25, 9, 30),
          reason: 'Richiesta di modifica RM-000321',
          expectedVersion: 4,
        ),
        fixture('service_reschedule_request.json'),
      );
      expect(
        reassignRequestToJson(
          operatorId: 'opr-000207',
          reason: 'Operatrice indisponibile nel pomeriggio',
          expectedVersion: 5,
        ),
        fixture('service_reassign_request.json'),
      );
      expect(
        reasonRequestToJson(
          reason: 'Ricovero ospedaliero del paziente',
          expectedVersion: 5,
        ),
        fixture('service_cancel_request.json'),
      );
      expect(expectedVersionParams(3), {'expected_version': '3'});
    });

    test('richieste di modifica', () {
      expect(
        replyRequestToJson(
          message: 'Verifico con la famiglia e ti aggiorno entro le 10.',
          expectedVersion: 1,
        ),
        fixture('change_request_reply_request.json'),
      );
      expect(
        changeRequestResolutionToJson(
          RescheduleResolution(
            start: utc(25, 9),
            end: utc(25, 9, 30),
            message: 'Spostato alle 11:00 come richiesto.',
          ),
          expectedVersion: 2,
        ),
        fixture('change_request_resolve_request.json'),
      );
      expect(
        changeRequestResolutionToJson(
          const ReassignResolution(operatorId: 'opr-000207'),
          expectedVersion: 2,
        ),
        fixture('change_request_resolve_reassign_request.json'),
      );
      expect(
        changeRequestResolutionToJson(
          const KeepAssignmentResolution(
            message: 'L\'orario resta confermato: la visita è stata spostata.',
          ),
          expectedVersion: 2,
        ),
        fixture('change_request_resolve_keep_request.json'),
      );
    });

    test('operatori', () {
      expect(
        operatorDraftToJson(
          const OperatorDraft(
            firstName: 'Giulia',
            lastName: 'Ferrari',
            email: 'giulia.ferrari@peoplecare.example',
            phone: '+39 333 000 0215',
            qualification: 'OSS',
            primaryFacilityId: 'str-000001',
            secondaryFacilityIds: ['str-000002'],
          ),
        ),
        fixture('operator_create_request.json'),
      );
      expect(
        operatorStatusRequestToJson(
          status: OperatorStatus.sospeso,
          reason: 'Congedo fino al 15/10',
          expectedVersion: 7,
        ),
        fixture('operator_status_request.json'),
      );
      expect(
        linkAccountRequestToJson(
          username: 'anna.mariani@peoplecare.example',
          expectedVersion: 7,
        ),
        fixture('operator_account_request.json'),
      );
    });
  });

  group('errori', () {
    test('formato standard', () {
      expect(
        exceptionFromApiError(422, fixture('error_validation.json')),
        isA<ValidationException>()
            .having(
              (e) => e.message,
              'message',
              'Controlla i dati del servizio.',
            )
            .having(
              (e) => e.fieldErrors,
              'fieldErrors',
              containsPair('address', 'Indica l\'indirizzo.'),
            ),
      );
      expect(
        exceptionFromApiError(409, fixture('error_version_conflict.json')),
        isA<ConcurrencyConflictException>(),
      );
      expect(
        exceptionFromApiError(409, fixture('error_operation_not_allowed.json')),
        isA<OperationNotAllowedException>().having(
          (e) => e.message,
          'message',
          contains('storico'),
        ),
      );
    });

    test('senza corpo decide lo status HTTP', () {
      expect(exceptionFromApiError(401, null), isA<UnauthenticatedException>());
      expect(
        exceptionFromApiError(403, null),
        isA<PermissionDeniedException>(),
      );
      expect(exceptionFromApiError(404, 'x'), isA<NotFoundException>());
      expect(
        exceptionFromApiError(409, null),
        isA<ConcurrencyConflictException>(),
      );
      expect(exceptionFromApiError(503, null), isA<ConnectivityException>());
      expect(
        exceptionFromApiError(500, {'error': 'testo'}),
        isA<UnexpectedRepositoryException>(),
      );
    });
  });

  test('stream degli eventi in tempo reale (SSE)', () async {
    final lines = Stream.fromIterable(
      const LineSplitter().convert(
        File('$fixturesDir/events_stream.txt').readAsStringSync(),
      ),
    );
    final messages = await lines.transform(const SseDecoder()).toList();
    expect(messages.map((m) => m.id), ['88121', '88122', '88123']);
    final live = messages.map(liveMessageFromSse).toList();
    expect(
      live[0],
      isA<LiveOperationalEvent>()
          .having((m) => m.event.topic, 'topic', OperationalEventTopic.servizi)
          .having((m) => m.event.entityId, 'entityId', 'srv-004812'),
    );
    expect(
      live[1],
      isA<LiveNotification>().having(
        (m) => m.notification.type,
        'type',
        NotificationType.servizioIniziato,
      ),
    );
    // Argomento sconosciuto: ignorato.
    expect(live[2], isNull);
    expect(
      liveMessageFromSse(const SseMessage(event: 'notification', data: '{')),
      isNull,
    );
  });

  test('API_CONTRACT.md riporta esattamente gli esempi verificati', () {
    final doc = File('API_CONTRACT.md').readAsStringSync();
    final pattern = RegExp(
      r'<!-- esempio: ([\w.]+) -->\s*```(json|text)\n([\s\S]*?)\n```',
    );
    final examples = pattern.allMatches(doc).toList();
    final referenced = <String>{};
    for (final match in examples) {
      final name = match.group(1)!;
      final body = match.group(3)!;
      referenced.add(name);
      if (match.group(2) == 'json') {
        expect(jsonDecode(body), fixture(name), reason: name);
      } else {
        expect(
          body.trimRight(),
          File('$fixturesDir/$name').readAsStringSync().trimRight(),
          reason: name,
        );
      }
    }
    final files = Directory(fixturesDir)
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toSet();
    expect(
      referenced,
      files,
      reason: 'ogni esempio deve comparire nel documento',
    );
  });
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peoplecare_central_operations/src/domain/domain.dart';

import '../support/test_support.dart';

void main() {
  late PeopleCareRepositories repos;
  late List<OperationalEvent> events;

  setUp(() {
    repos = createTestRepositories();
    events = [];
    repos.events.watchEvents().listen(events.add);
  });

  tearDown(() => repos.dispose());

  Future<void> flushEvents() => Future<void>.delayed(Duration.zero);

  Future<ServiceDraft> newDraft({String? operatorId}) async {
    final facility = (await repos.facilities.listFacilities()).first;
    final type = (await repos.serviceTypes.listServiceTypes()).firstWhere(
      (t) => t.isActive,
    );
    final patient = (await repos.patients.searchPatients('')).first;
    final start = atTime(addDays(testNow, 3), 9, 0);
    return ServiceDraft(
      kind: CatalogServiceKind(serviceTypeId: type.id, name: type.name),
      scheduledStart: start,
      scheduledEnd: start.add(Duration(minutes: type.defaultDurationMinutes)),
      patient: RegisteredServicePatient(
        patientId: patient.id,
        firstName: patient.firstName,
        lastName: patient.lastName,
      ),
      facilityId: facility.id,
      operatorId: operatorId,
      priority: ServicePriority.alta,
      address: 'Via di prova 1, Bergamo',
      phone: '+39 035 000 9999',
    );
  }

  Future<Operator> activeOperator() async =>
      (await repos.operators.listOperators(
        const OperatorQuery(statuses: {OperatorStatus.attivo}),
      )).first;

  group('servizi', () {
    test(
      'creazione: da assegnare senza operatore, assegnato con operatore',
      () async {
        final unassigned = await repos.services.createService(await newDraft());
        expect(unassigned.status, ServiceStatus.daAssegnare);
        expect(unassigned.code, matches(RegExp(r'^SRV-2026-\d{6}$')));
        expect(unassigned.version, 1);

        final operator = await activeOperator();
        final assigned = await repos.services.createService(
          await newDraft(operatorId: operator.id),
        );
        expect(assigned.status, ServiceStatus.assegnato);
        expect(assigned.operatorId, operator.id);

        final history = await repos.services.getServiceHistory(assigned.id);
        expect(history.single.action, AuditActions.serviceCreated);
        await flushEvents();
        expect(
          events.where((e) => e.topic == OperationalEventTopic.servizi),
          isNotEmpty,
        );
      },
    );

    test('validazione con errori per campo', () async {
      final draft = await newDraft();
      final invalid = ServiceDraft(
        kind: const CustomServiceKind('  '),
        scheduledStart: draft.scheduledStart,
        scheduledEnd: draft.scheduledStart,
        patient: const ManualServicePatient(firstName: '', lastName: ''),
        facilityId: 'inesistente',
        address: ' ',
        phone: 'abc',
      );
      await expectLater(
        repos.services.createService(invalid),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.fieldErrors.keys,
            'campi',
            containsAll([
              'custom_type_name',
              'scheduled_end',
              'patient',
              'facility_id',
              'address',
              'phone',
            ]),
          ),
        ),
      );
    });

    test('concorrenza ottimistica sulla versione', () async {
      final created = await repos.services.createService(await newDraft());
      final moved = await repos.services.rescheduleService(
        created.id,
        start: created.scheduledStart.add(const Duration(hours: 1)),
        end: created.scheduledEnd.add(const Duration(hours: 1)),
        expectedVersion: created.version,
      );
      expect(moved.version, created.version + 1);
      await expectLater(
        repos.services.cancelService(
          created.id,
          reason: 'Doppione',
          expectedVersion: created.version,
        ),
        throwsA(isA<ConcurrencyConflictException>()),
      );
    });

    test(
      'riassegnazione, da riprogrammare, riprogrammazione e annullamento',
      () async {
        final operator = await activeOperator();
        var service = await repos.services.createService(await newDraft());

        service = await repos.services.reassignService(
          service.id,
          operatorId: operator.id,
          expectedVersion: service.version,
        );
        expect(service.status, ServiceStatus.assegnato);

        service = await repos.services.markToReschedule(
          service.id,
          reason: 'Paziente ricoverato',
          expectedVersion: service.version,
        );
        expect(service.status, ServiceStatus.daRiprogrammare);
        expect(service.statusReason, 'Paziente ricoverato');

        service = await repos.services.rescheduleService(
          service.id,
          start: service.scheduledStart.add(const Duration(days: 1)),
          end: service.scheduledEnd.add(const Duration(days: 1)),
          expectedVersion: service.version,
        );
        expect(service.status, ServiceStatus.assegnato);
        expect(service.statusReason, isNull);

        await expectLater(
          repos.services.cancelService(
            service.id,
            reason: ' ',
            expectedVersion: service.version,
          ),
          throwsA(isA<ValidationException>()),
        );
        service = await repos.services.cancelService(
          service.id,
          reason: 'Richiesta della famiglia',
          expectedVersion: service.version,
        );
        expect(service.status, ServiceStatus.annullato);
        await expectLater(
          repos.services.rescheduleService(
            service.id,
            start: service.scheduledStart,
            end: service.scheduledEnd,
            expectedVersion: service.version,
          ),
          throwsA(isA<OperationNotAllowedException>()),
        );

        final history = await repos.services.getServiceHistory(service.id);
        expect(history.first.action, AuditActions.serviceCancelled);
        expect(history.map((e) => e.action), [
          AuditActions.serviceCancelled,
          AuditActions.serviceRescheduled,
          AuditActions.serviceMarkedToReschedule,
          AuditActions.serviceReassigned,
          AuditActions.serviceCreated,
        ]);
        expect(
          history[1].changes.map((c) => c.field),
          containsAll(['scheduled_start', 'scheduled_end']),
        );
      },
    );

    test('non si assegna a un operatore sospeso', () async {
      final suspended = (await repos.operators.listOperators(
        const OperatorQuery(statuses: {OperatorStatus.sospeso}),
      )).first;
      final service = await repos.services.createService(await newDraft());
      await expectLater(
        repos.services.reassignService(
          service.id,
          operatorId: suspended.id,
          expectedVersion: service.version,
        ),
        throwsA(isA<OperationNotAllowedException>()),
      );
    });

    test('eliminazione consentita solo quando la policy lo permette', () async {
      final operator = await activeOperator();
      final assigned = await repos.services.createService(
        await newDraft(operatorId: operator.id),
      );
      await expectLater(
        repos.services.deleteService(
          assigned.id,
          expectedVersion: assigned.version,
        ),
        throwsA(isA<OperationNotAllowedException>()),
      );

      final unassigned = await repos.services.createService(await newDraft());
      await repos.services.deleteService(
        unassigned.id,
        expectedVersion: unassigned.version,
      );
      await expectLater(
        repos.services.getService(unassigned.id),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('ricerca con filtri, ordinamento e paginazione', () async {
      final week = DateRange.week(testNow);
      final all = await repos.services.searchServices(
        ServiceQuery(range: week),
        page: const PageRequest(pageSize: 20),
      );
      expect(all.total, greaterThan(20));
      expect(all.items, hasLength(20));
      final starts = all.items.map((s) => s.scheduledStart).toList();
      expect([...starts]..sort(), starts);

      final completed = await repos.services.searchServices(
        ServiceQuery(range: week, statuses: const {ServiceStatus.completato}),
        page: const PageRequest(pageSize: 500),
      );
      expect(
        completed.items.every((s) => s.status == ServiceStatus.completato),
        isTrue,
      );

      final unassigned = await repos.services.searchServices(
        ServiceQuery(range: week, operator: const Unassigned()),
        page: const PageRequest(pageSize: 500),
      );
      expect(unassigned.items.every((s) => s.operatorId == null), isTrue);

      final byCode = await repos.services.searchServices(
        ServiceQuery(search: all.items.first.code),
      );
      expect(byCode.items.first.id, all.items.first.id);

      final descending = await repos.services.searchServices(
        ServiceQuery(range: week, sort: ServiceSort.code, descending: true),
        page: const PageRequest(pageSize: 5),
      );
      final codes = descending.items.map((s) => s.code).toList();
      expect([...codes]..sort((a, b) => b.compareTo(a)), codes);
    });

    test('il calendario rifiuta intervalli oltre 31 giorni', () async {
      await expectLater(
        repos.services.listServicesInRange(
          DateRange(testNow, addDays(testNow, 40)),
        ),
        throwsA(isA<ValidationException>()),
      );
      final today = await repos.services.listServicesInRange(
        DateRange.day(testNow),
      );
      expect(today, isNotEmpty);
    });
  });

  group('richieste di modifica', () {
    test('risposta e chiusura con nuovo orario', () async {
      final pending = (await repos.changeRequests.listChangeRequests(
        const ChangeRequestQuery(statuses: {ChangeRequestStatus.inAttesa}),
      )).first;
      final replied = await repos.changeRequests.reply(
        pending.id,
        message: 'Verifico e ti aggiorno.',
        expectedVersion: pending.version,
      );
      expect(replied.status, ChangeRequestStatus.inLavorazione);
      expect(replied.messages.last.authorKind, ActorKind.centrale);

      final service = await repos.services.getService(pending.serviceId);
      final newStart = atTime(addDays(testNow, 5), 15, 0);
      final closed = await repos.changeRequests.resolve(
        replied.id,
        RescheduleResolution(
          start: newStart,
          end: newStart.add(service.scheduledDuration),
          message: 'Spostato alle 15:00.',
        ),
        expectedVersion: replied.version,
      );
      expect(closed.status, ChangeRequestStatus.chiusa);
      expect(closed.outcome, ChangeRequestOutcome.orarioModificato);
      expect(closed.closedBy, isNotNull);

      final updated = await repos.services.getService(pending.serviceId);
      expect(updated.scheduledStart, newStart);
      expect(
        updated.openChangeRequestCount,
        service.openChangeRequestCount - 1,
      );

      await expectLater(
        repos.changeRequests.reply(
          closed.id,
          message: 'Altro',
          expectedVersion: closed.version,
        ),
        throwsA(isA<OperationNotAllowedException>()),
      );
    });

    test('chiusura mantenendo l\'assegnazione', () async {
      final open = (await repos.changeRequests.listChangeRequests(
        const ChangeRequestQuery(
          statuses: {
            ChangeRequestStatus.inAttesa,
            ChangeRequestStatus.inLavorazione,
          },
        ),
      )).last;
      final before = await repos.services.getService(open.serviceId);
      final closed = await repos.changeRequests.resolve(
        open.id,
        const KeepAssignmentResolution(message: 'Confermato.'),
        expectedVersion: open.version,
      );
      expect(closed.outcome, ChangeRequestOutcome.assegnazioneMantenuta);
      final after = await repos.services.getService(open.serviceId);
      expect(after.operatorId, before.operatorId);
      expect(after.scheduledStart, before.scheduledStart);
    });
  });

  group('documenti e notifiche', () {
    test('caricamento, download, verifica ed eliminazione', () async {
      final service = await repos.services.createService(await newDraft());
      final uploaded = await repos.documents.uploadDocument(
        DocumentUpload(
          owner: DocumentOwner(
            type: DocumentOwnerType.servizio,
            id: service.id,
          ),
          title: 'Piano assistenziale',
          fileName: 'piano.pdf',
          mimeType: 'application/pdf',
          bytes: Uint8List.fromList([1, 2, 3]),
          category: DocumentCategory.pianoAssistenziale,
        ),
      );
      expect(uploaded.source, DocumentSource.centrale);
      expect(uploaded.owner.label, contains(service.code));
      expect((await repos.services.getService(service.id)).documentCount, 1);

      final content = await repos.documents.downloadDocument(uploaded.id);
      expect(content.bytes, [1, 2, 3]);

      final found = await repos.documents.searchDocuments(
        DocumentQuery(
          ownerType: DocumentOwnerType.servizio,
          ownerId: service.id,
        ),
      );
      expect(found.items.single.id, uploaded.id);

      await repos.documents.deleteDocument(uploaded.id);
      expect((await repos.services.getService(service.id)).documentCount, 0);

      await expectLater(
        repos.documents.uploadDocument(
          DocumentUpload(
            owner: const DocumentOwner.centrale(),
            title: 'Vuoto',
            fileName: 'vuoto.txt',
            mimeType: 'text/plain',
            bytes: Uint8List(0),
            category: DocumentCategory.altro,
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test(
      'i documenti ricevuti dal territorio si verificano, non si eliminano',
      () async {
        final pending = (await repos.documents.searchDocuments(
          const DocumentQuery(pendingReviewOnly: true),
        )).items.first;
        expect(pending.source, DocumentSource.operatore);
        final reviewed = await repos.documents.markReviewed(pending.id);
        expect(reviewed.isPendingReview, isFalse);
        expect(reviewed.reviewedBy, isNotNull);
        await expectLater(
          repos.documents.deleteDocument(pending.id),
          throwsA(isA<OperationNotAllowedException>()),
        );
      },
    );

    test('notifiche lette e non lette', () async {
      final unread = await repos.notifications.countUnread();
      expect(unread, greaterThan(0));
      final first = (await repos.notifications.listNotifications(
        const NotificationQuery(unreadOnly: true),
      )).first;
      await repos.notifications.markRead(first.id);
      expect(await repos.notifications.countUnread(), unread - 1);
      await repos.notifications.markAllRead();
      expect(await repos.notifications.countUnread(), 0);
    });
  });

  group('anagrafiche', () {
    test(
      'operatore: creazione con codice, strutture multiple, stato e account',
      () async {
        final facilities = await repos.facilities.listFacilities();
        final created = await repos.operators.createOperator(
          OperatorDraft(
            firstName: 'Giulia',
            lastName: 'Test',
            email: 'giulia.test@peoplecare.example',
            phone: '+39 333 000 1234',
            qualification: 'OSS',
            primaryFacilityId: facilities[0].id,
            // Duplicati e struttura principale vengono ripuliti.
            secondaryFacilityIds: [
              facilities[1].id,
              facilities[0].id,
              facilities[1].id,
            ],
          ),
        );
        expect(created.code, matches(RegExp(r'^OP-\d{6}$')));
        expect(created.secondaryFacilityIds, [facilities[1].id]);
        expect(created.belongsTo(facilities[1].id), isTrue);

        await expectLater(
          repos.operators.changeStatus(
            created.id,
            OperatorStatus.sospeso,
            expectedVersion: created.version,
          ),
          throwsA(isA<ValidationException>()),
        );
        final suspended = await repos.operators.changeStatus(
          created.id,
          OperatorStatus.sospeso,
          reason: 'Malattia',
          expectedVersion: created.version,
        );
        expect(suspended.isAssignable, isFalse);

        final linked = await repos.operators.linkAccount(
          created.id,
          username: 'Giulia.Test@PeopleCare.example',
          expectedVersion: suspended.version,
        );
        expect(linked.account?.username, 'giulia.test@peoplecare.example');
        expect(linked.account?.status, AccountStatus.invitato);
        final unlinked = await repos.operators.unlinkAccount(
          created.id,
          expectedVersion: linked.version,
        );
        expect(unlinked.hasAccount, isFalse);

        await expectLater(
          repos.operators.createOperator(
            OperatorDraft(
              firstName: 'Altro',
              lastName: 'Operatore',
              email: 'giulia.test@peoplecare.example',
              phone: '+39 333 000 5678',
              qualification: 'OSS',
              primaryFacilityId: facilities[0].id,
            ),
          ),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.fieldErrors.keys,
              'campi',
              contains('email'),
            ),
          ),
        );
      },
    );

    test('struttura e tipologia: nomi univoci e versione', () async {
      final facility = await repos.facilities.createFacility(
        const FacilityDraft(
          name: 'Comunità alloggio Test',
          kind: FacilityKind.comunitaAlloggio,
          address: 'Via Test 3',
          city: 'Bergamo',
        ),
      );
      expect(facility.code, matches(RegExp(r'^STR-\d{2}$')));
      await expectLater(
        repos.facilities.createFacility(
          const FacilityDraft(
            name: 'comunita alloggio test',
            kind: FacilityKind.altro,
            address: 'Via Altra 1',
            city: 'Bergamo',
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
      final updated = await repos.facilities.updateFacility(
        facility.id,
        FacilityDraft.fromFacility(facility.copyWith(isActive: false)),
        expectedVersion: facility.version,
      );
      expect(updated.isActive, isFalse);
      expect(updated.version, facility.version + 1);

      final type = await repos.serviceTypes.createServiceType(
        const ServiceTypeDraft(
          name: 'Tipologia di prova',
          category: 'Assistenza di base',
          defaultDurationMinutes: 40,
          requiredQualifications: ['OSS'],
        ),
      );
      expect(type.acceptsQualification('OSS'), isTrue);
      expect(type.acceptsQualification('Infermiere'), isFalse);
    });
  });

  test('report operativo della settimana', () async {
    final report = await repos.reports.getOperationalReport(
      ReportQuery(period: DateRange.week(testNow)),
    );
    expect(report.totalServices, greaterThan(0));
    expect(report.daily, hasLength(7));
    expect(report.operators, isNotEmpty);
  });

  test('registro attività filtrabile per attore', () async {
    final page = await repos.audit.searchAudit(
      const AuditQuery(actorKinds: {ActorKind.operatore}),
      page: const PageRequest(pageSize: 30),
    );
    expect(page.items, isNotEmpty);
    expect(page.items.every((e) => e.actorKind == ActorKind.operatore), isTrue);
  });
}

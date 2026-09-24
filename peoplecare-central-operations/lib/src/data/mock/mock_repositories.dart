import '../../core/clock.dart';
import '../../core/text.dart';
import '../../domain/domain.dart';
import 'demo_catalog.dart';
import 'demo_seeder.dart';
import 'live_activity_simulator.dart';
import 'mock_backend.dart';

/// Crea i repository DEMO in memoria, già popolati.
///
/// - [latency]: ritardo simulato di ogni chiamata;
/// - [simulateLiveActivity]: avvia il simulatore degli eventi dall'app mobile.
PeopleCareRepositories createMockRepositories({
  Clock clock = const SystemClock(),
  Duration latency = const Duration(milliseconds: 180),
  bool simulateLiveActivity = true,
  Duration simulationInterval = const Duration(seconds: 15),
}) {
  final backend = MockBackend(
    clock: clock,
    latency: latency,
    currentUser: CentralUser(
      id: demoCentralUser.id,
      displayName: demoCentralUser.name,
      role: demoCentralUser.role,
    ),
  );
  DemoDataSeeder(backend).seed();
  final simulator = LiveActivitySimulator(
    backend,
    interval: simulationInterval,
  );
  if (simulateLiveActivity) simulator.start();
  return createRepositoriesForBackend(
    backend,
    onDispose: () async {
      simulator.stop();
      await backend.dispose();
    },
  );
}

/// Espone un [MockBackend] esistente attraverso le interfacce dei repository.
PeopleCareRepositories createRepositoriesForBackend(
  MockBackend backend, {
  Future<void> Function()? onDispose,
}) {
  return PeopleCareRepositories(
    dataSource: const DataSourceInfo(
      name: 'Demo',
      isDemo: true,
      description:
          'Dati fittizi generati in memoria: nessun collegamento al sistema '
          'PeopleCare. Le modifiche si perdono alla chiusura.',
    ),
    session: MockSessionRepository(backend),
    operators: MockOperatorRepository(backend),
    facilities: MockFacilityRepository(backend),
    serviceTypes: MockServiceTypeRepository(backend),
    patients: MockPatientRepository(backend),
    services: MockServiceRepository(backend),
    changeRequests: MockChangeRequestRepository(backend),
    documents: MockDocumentRepository(backend),
    notifications: MockNotificationRepository(backend),
    audit: MockAuditRepository(backend),
    reports: MockReportRepository(backend),
    events: MockOperationalEventsRepository(backend),
    onDispose: onDispose ?? backend.dispose,
  );
}

abstract class _MockRepository {
  _MockRepository(this.backend);

  final MockBackend backend;

  Future<T> run<T>(T Function() action) async {
    await backend.simulateLatency();
    return action();
  }
}

class MockSessionRepository extends _MockRepository
    implements SessionRepository {
  MockSessionRepository(super.backend);

  @override
  Future<CentralUser> getCurrentUser() => run(() => backend.currentUser);
}

class MockOperatorRepository extends _MockRepository
    implements OperatorRepository {
  MockOperatorRepository(super.backend);

  @override
  Future<List<Operator>> listOperators([
    OperatorQuery query = const OperatorQuery(),
  ]) => run(() {
    final search = query.search;
    return backend.operators.values
        .where(
          (o) =>
              (query.facilityId == null || o.belongsTo(query.facilityId!)) &&
              (query.statuses.isEmpty || query.statuses.contains(o.status)) &&
              (query.qualification == null ||
                  o.qualification == query.qualification) &&
              (search == null ||
                  matchesSearch(search, [
                    o.firstName,
                    o.lastName,
                    o.code,
                    o.email,
                    o.phone,
                    o.qualification,
                  ])),
        )
        .toList()
      ..sort((a, b) => a.sortName.compareTo(b.sortName));
  });

  @override
  Future<Operator> getOperator(String id) => run(() => backend.operator(id));

  @override
  Future<List<String>> listQualifications() =>
      run(() => List.unmodifiable(backend.qualifications));

  @override
  Future<Operator> createOperator(OperatorDraft draft) =>
      run(() => backend.createOperator(draft));

  @override
  Future<Operator> updateOperator(
    String id,
    OperatorDraft draft, {
    required int expectedVersion,
  }) => run(() => backend.updateOperator(id, draft, expectedVersion));

  @override
  Future<Operator> changeStatus(
    String id,
    OperatorStatus status, {
    String? reason,
    required int expectedVersion,
  }) => run(
    () => backend.changeOperatorStatus(id, status, reason, expectedVersion),
  );

  @override
  Future<Operator> linkAccount(
    String id, {
    required String username,
    required int expectedVersion,
  }) => run(() => backend.linkAccount(id, username, expectedVersion));

  @override
  Future<Operator> unlinkAccount(String id, {required int expectedVersion}) =>
      run(() => backend.unlinkAccount(id, expectedVersion));
}

class MockFacilityRepository extends _MockRepository
    implements FacilityRepository {
  MockFacilityRepository(super.backend);

  @override
  Future<List<Facility>> listFacilities() => run(
    () =>
        backend.facilities.values.toList()
          ..sort((a, b) => a.code.compareTo(b.code)),
  );

  @override
  Future<Facility> getFacility(String id) => run(() => backend.facility(id));

  @override
  Future<Facility> createFacility(FacilityDraft draft) =>
      run(() => backend.createFacility(draft));

  @override
  Future<Facility> updateFacility(
    String id,
    FacilityDraft draft, {
    required int expectedVersion,
  }) => run(() => backend.updateFacility(id, draft, expectedVersion));
}

class MockServiceTypeRepository extends _MockRepository
    implements ServiceTypeRepository {
  MockServiceTypeRepository(super.backend);

  @override
  Future<List<ServiceType>> listServiceTypes() => run(
    () =>
        backend.serviceTypes.values.toList()
          ..sort((a, b) => a.code.compareTo(b.code)),
  );

  @override
  Future<ServiceType> getServiceType(String id) =>
      run(() => backend.serviceType(id));

  @override
  Future<ServiceType> createServiceType(ServiceTypeDraft draft) =>
      run(() => backend.createServiceType(draft));

  @override
  Future<ServiceType> updateServiceType(
    String id,
    ServiceTypeDraft draft, {
    required int expectedVersion,
  }) => run(() => backend.updateServiceType(id, draft, expectedVersion));
}

class MockPatientRepository extends _MockRepository
    implements PatientRepository {
  MockPatientRepository(super.backend);

  @override
  Future<List<Patient>> searchPatients(
    String text, {
    String? facilityId,
    int limit = 20,
  }) => run(
    () =>
        (backend.patients.values
                .where(
                  (p) =>
                      (facilityId == null || p.facilityId == facilityId) &&
                      matchesSearch(text, [
                        p.firstName,
                        p.lastName,
                        p.code,
                        p.city,
                      ]),
                )
                .toList()
              ..sort((a, b) => a.sortName.compareTo(b.sortName)))
            .take(limit)
            .toList(),
  );

  @override
  Future<Patient> getPatient(String id) => run(() => backend.patient(id));
}

class MockServiceRepository extends _MockRepository
    implements ServiceRepository {
  MockServiceRepository(super.backend);

  @override
  Future<List<Service>> listServicesInRange(
    DateRange range, {
    Set<String> facilityIds = const {},
  }) => run(() {
    if (range.duration > const Duration(days: 32)) {
      throw const ValidationException(
        'L\'intervallo richiesto supera i 31 giorni.',
      );
    }
    return backend.services.values
        .where(
          (s) =>
              s.scheduledRange.overlaps(range) &&
              (facilityIds.isEmpty || facilityIds.contains(s.facilityId)),
        )
        .toList()
      ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
  });

  @override
  Future<PagedResult<Service>> searchServices(
    ServiceQuery query, {
    PageRequest page = const PageRequest(),
  }) => run(() {
    final matches = backend.services.values
        .where((s) => _matches(s, query))
        .toList();
    matches.sort((a, b) {
      final result = _compare(a, b, query.sort);
      final directed = query.descending ? -result : result;
      return directed != 0
          ? directed
          : a.scheduledStart.compareTo(b.scheduledStart);
    });
    return PagedResult.fromAll(matches, page);
  });

  bool _matches(Service s, ServiceQuery q) {
    final range = q.range;
    if (range != null && !s.scheduledRange.overlaps(range)) return false;
    if (q.facilityIds.isNotEmpty && !q.facilityIds.contains(s.facilityId)) {
      return false;
    }
    switch (q.operator) {
      case AssignedTo(:final operatorId):
        if (s.operatorId != operatorId) return false;
      case Unassigned():
        if (s.operatorId != null) return false;
      case null:
        break;
    }
    if (q.patientId != null && s.patient.patientId != q.patientId) {
      return false;
    }
    final patientText = q.patientText;
    if (patientText != null &&
        !matchesSearch(patientText, [
          s.patient.firstName,
          s.patient.lastName,
        ])) {
      return false;
    }
    if (q.serviceTypeId != null && s.serviceTypeId != q.serviceTypeId) {
      return false;
    }
    if (q.customTypeOnly && !s.isCustom) return false;
    if (q.statuses.isNotEmpty && !q.statuses.contains(s.status)) return false;
    if (q.priorities.isNotEmpty && !q.priorities.contains(s.priority)) {
      return false;
    }
    final search = q.search;
    if (search != null &&
        !matchesSearch(search, [
          s.code,
          s.patient.firstName,
          s.patient.lastName,
          s.kind.label,
          s.address,
          s.notes,
          backend.operators[s.operatorId]?.fullName,
        ])) {
      return false;
    }
    return true;
  }

  int _compare(Service a, Service b, ServiceSort sort) => switch (sort) {
    ServiceSort.scheduledStart => a.scheduledStart.compareTo(b.scheduledStart),
    ServiceSort.code => a.code.compareTo(b.code),
    ServiceSort.patient => a.patient.sortName.compareTo(b.patient.sortName),
    ServiceSort.status => a.status.index.compareTo(b.status.index),
    ServiceSort.priority => b.priority.rank.compareTo(a.priority.rank),
    ServiceSort.facility =>
      (backend.facilities[a.facilityId]?.name ?? '').compareTo(
        backend.facilities[b.facilityId]?.name ?? '',
      ),
  };

  @override
  Future<Service> getService(String id) => run(() => backend.service(id));

  @override
  Future<Service> createService(ServiceDraft draft) =>
      run(() => backend.createService(draft));

  @override
  Future<Service> updateService(
    String id,
    ServiceDraft draft, {
    required int expectedVersion,
  }) => run(() => backend.updateService(id, draft, expectedVersion));

  @override
  Future<Service> rescheduleService(
    String id, {
    required DateTime start,
    required DateTime end,
    String? reason,
    required int expectedVersion,
  }) => run(
    () => backend.rescheduleService(
      id,
      start: start,
      end: end,
      reason: reason,
      expectedVersion: expectedVersion,
    ),
  );

  @override
  Future<Service> reassignService(
    String id, {
    required String? operatorId,
    String? reason,
    required int expectedVersion,
  }) => run(
    () => backend.reassignService(
      id,
      operatorId: operatorId,
      reason: reason,
      expectedVersion: expectedVersion,
    ),
  );

  @override
  Future<Service> cancelService(
    String id, {
    required String reason,
    required int expectedVersion,
  }) => run(() => backend.cancelService(id, reason, expectedVersion));

  @override
  Future<Service> markToReschedule(
    String id, {
    required String reason,
    required int expectedVersion,
  }) => run(() => backend.markToReschedule(id, reason, expectedVersion));

  @override
  Future<void> deleteService(String id, {required int expectedVersion}) =>
      run(() => backend.deleteService(id, expectedVersion));

  @override
  Future<List<AuditEntry>> getServiceHistory(String id) => run(
    () => newestFirst(
      backend.auditLog.where((e) => e.serviceId == id),
      (e) => e.occurredAt,
    ),
  );
}

class MockChangeRequestRepository extends _MockRepository
    implements ChangeRequestRepository {
  MockChangeRequestRepository(super.backend);

  @override
  Future<List<ChangeRequest>> listChangeRequests([
    ChangeRequestQuery query = const ChangeRequestQuery(),
  ]) => run(() {
    final search = query.search;
    final matches = backend.changeRequests.values.where((r) {
      if (query.statuses.isNotEmpty && !query.statuses.contains(r.status)) {
        return false;
      }
      if (query.reasons.isNotEmpty && !query.reasons.contains(r.reason)) {
        return false;
      }
      if (query.operatorId != null && r.operatorId != query.operatorId) {
        return false;
      }
      if (query.serviceId != null && r.serviceId != query.serviceId) {
        return false;
      }
      final service = backend.services[r.serviceId];
      if (query.facilityId != null && service?.facilityId != query.facilityId) {
        return false;
      }
      if (search != null &&
          !matchesSearch(search, [
            r.code,
            r.serviceCode,
            r.operatorName,
            r.message,
            service?.patient.fullName,
          ])) {
        return false;
      }
      return true;
    });
    return newestFirst(matches, (r) => r.createdAt);
  });

  @override
  Future<ChangeRequest> getChangeRequest(String id) =>
      run(() => backend.changeRequest(id));

  @override
  Future<ChangeRequest> reply(
    String id, {
    required String message,
    required int expectedVersion,
  }) => run(() => backend.replyToChangeRequest(id, message, expectedVersion));

  @override
  Future<ChangeRequest> resolve(
    String id,
    ChangeRequestResolution resolution, {
    required int expectedVersion,
  }) =>
      run(() => backend.resolveChangeRequest(id, resolution, expectedVersion));
}

class MockDocumentRepository extends _MockRepository
    implements DocumentRepository {
  MockDocumentRepository(super.backend);

  @override
  Future<PagedResult<DocumentInfo>> searchDocuments(
    DocumentQuery query, {
    PageRequest page = const PageRequest(),
  }) => run(() {
    final search = query.search;
    final matches = backend.documents.values.where((d) {
      if (query.ownerType != null && d.owner.type != query.ownerType) {
        return false;
      }
      if (query.ownerId != null && d.owner.id != query.ownerId) return false;
      if (query.categories.isNotEmpty &&
          !query.categories.contains(d.category)) {
        return false;
      }
      if (query.source != null && d.source != query.source) return false;
      if (query.pendingReviewOnly && !d.isPendingReview) return false;
      final range = query.range;
      if (range != null && !range.contains(d.uploadedAt)) return false;
      if (search != null &&
          !matchesSearch(search, [
            d.title,
            d.fileName,
            d.owner.label,
            d.uploadedBy,
            d.description,
          ])) {
        return false;
      }
      return true;
    });
    return PagedResult.fromAll(newestFirst(matches, (d) => d.uploadedAt), page);
  });

  @override
  Future<DocumentInfo> uploadDocument(DocumentUpload upload) =>
      run(() => backend.uploadDocument(upload));

  @override
  Future<DocumentContent> downloadDocument(String id) =>
      run(() => backend.downloadDocument(id));

  @override
  Future<DocumentInfo> markReviewed(String id) =>
      run(() => backend.markDocumentReviewed(id));

  @override
  Future<void> deleteDocument(String id) =>
      run(() => backend.deleteDocument(id));
}

class MockNotificationRepository extends _MockRepository
    implements NotificationRepository {
  MockNotificationRepository(super.backend);

  @override
  Future<List<AppNotification>> listNotifications([
    NotificationQuery query = const NotificationQuery(),
  ]) => run(
    () => backend.notifications.reversed
        .where(
          (n) =>
              (!query.unreadOnly || !n.isRead) &&
              (query.types.isEmpty || query.types.contains(n.type)),
        )
        .take(query.limit)
        .toList(),
  );

  @override
  Future<int> countUnread() =>
      run(() => backend.notifications.where((n) => !n.isRead).length);

  @override
  Future<void> markRead(String id) =>
      run(() => backend.markNotificationRead(id));

  @override
  Future<void> markAllRead() => run(backend.markAllNotificationsRead);

  @override
  Stream<AppNotification> watchNew() => backend.newNotifications;
}

class MockAuditRepository extends _MockRepository implements AuditRepository {
  MockAuditRepository(super.backend);

  @override
  Future<PagedResult<AuditEntry>> searchAudit(
    AuditQuery query, {
    PageRequest page = const PageRequest(),
  }) => run(() {
    final search = query.search;
    final matches = backend.auditLog.reversed.where((e) {
      final range = query.range;
      if (range != null && !range.contains(e.occurredAt)) return false;
      if (query.actorKinds.isNotEmpty &&
          !query.actorKinds.contains(e.actorKind)) {
        return false;
      }
      if (query.entityTypes.isNotEmpty &&
          !query.entityTypes.contains(e.entityType)) {
        return false;
      }
      if (query.entityId != null && e.entityId != query.entityId) return false;
      if (query.serviceId != null && e.serviceId != query.serviceId) {
        return false;
      }
      if (search != null &&
          !matchesSearch(search, [
            e.summary,
            e.entityLabel,
            e.actorName,
            e.action,
          ])) {
        return false;
      }
      return true;
    }).toList();
    return PagedResult.fromAll(matches, page);
  });
}

class MockReportRepository extends _MockRepository implements ReportRepository {
  MockReportRepository(super.backend);

  @override
  Future<OperationalReport> getOperationalReport(ReportQuery query) => run(
    () => const ReportCalculator().compute(
      query: query,
      services: backend.services.values,
      changeRequests: backend.changeRequests.values,
      operatorsById: backend.operators,
      facilitiesById: backend.facilities,
      generatedAt: backend.now,
    ),
  );
}

class MockOperationalEventsRepository extends _MockRepository
    implements OperationalEventsRepository {
  MockOperationalEventsRepository(super.backend);

  @override
  Stream<OperationalEvent> watchEvents() => backend.events;
}

/// Ordina dal più recente; a parità di istante vince l'ultimo inserito
/// (`List.sort` non è stabile).
List<T> newestFirst<T>(Iterable<T> items, DateTime Function(T item) at) {
  final indexed = items.indexed.toList()
    ..sort((a, b) {
      final byTime = at(b.$2).compareTo(at(a.$2));
      return byTime != 0 ? byTime : b.$1.compareTo(a.$1);
    });
  return [for (final (_, item) in indexed) item];
}

import 'dart:async';
import 'dart:typed_data';

import '../../core/clock.dart';
import '../../core/text.dart';
import '../../domain/domain.dart';
import 'demo_pdf.dart';

/// Sistema PeopleCare simulato in memoria. SOLO DEMO.
///
/// Si comporta come ci si aspetta dal sistema reale (vedi API_CONTRACT.md):
/// assegna codici, controlla versioni e regole di stato, scrive il registro
/// attività, genera notifiche ed eventi in tempo reale. Nessun dato lascia la
/// memoria del processo e tutto si perde alla chiusura dell'applicazione.
class MockBackend {
  MockBackend({
    required this.clock,
    required this.currentUser,
    this.latency = Duration.zero,
  });

  final Clock clock;
  final CentralUser currentUser;

  /// Ritardo artificiale di ogni chiamata, per rendere visibili i caricamenti.
  final Duration latency;

  final Map<String, Facility> facilities = {};
  final Map<String, ServiceType> serviceTypes = {};
  final Map<String, Operator> operators = {};
  final Map<String, Patient> patients = {};
  final Map<String, Service> services = {};
  final Map<String, ChangeRequest> changeRequests = {};
  final Map<String, DocumentInfo> documents = {};
  final Map<String, Uint8List> documentContents = {};
  final List<AppNotification> notifications = [];
  final List<AuditEntry> auditLog = [];
  final List<String> qualifications = [];

  /// Servizi che la simulazione non avvia da sola (per mostrare i ritardi).
  final Set<String> stalledServiceIds = {};

  /// Servizi per cui è già stata inviata la notifica di avvio in ritardo.
  final Set<String> lateNotifiedServiceIds = {};

  final _events = StreamController<OperationalEvent>.broadcast();
  final _newNotifications = StreamController<AppNotification>.broadcast();

  int _idSequence = 0;
  int nextServiceNumber = 4200;
  int nextOperatorNumber = 100;
  int nextChangeRequestNumber = 300;
  int nextFacilityNumber = 1;
  int nextServiceTypeNumber = 1;

  /// Dimensione massima di un allegato.
  static const maxUploadBytes = 20 * 1024 * 1024;

  DateTime get now => clock.now();

  Stream<OperationalEvent> get events => _events.stream;

  Stream<AppNotification> get newNotifications => _newNotifications.stream;

  Future<void> simulateLatency() =>
      latency == Duration.zero ? Future<void>.value() : Future.delayed(latency);

  String newId(String prefix) {
    _idSequence++;
    return '$prefix-${_idSequence.toString().padLeft(6, '0')}';
  }

  void emit(OperationalEventTopic topic, [String? entityId]) {
    if (_events.isClosed) return;
    _events.add(
      OperationalEvent(topic: topic, entityId: entityId, occurredAt: now),
    );
  }

  Future<void> dispose() async {
    await _events.close();
    await _newNotifications.close();
  }

  // ---------------------------------------------------------------------------
  // Letture di supporto
  // ---------------------------------------------------------------------------

  Facility facility(String id) =>
      facilities[id] ??
      (throw const NotFoundException('Struttura non trovata.'));

  Operator operator(String id) =>
      operators[id] ??
      (throw const NotFoundException('Operatore non trovato.'));

  Service service(String id) =>
      services[id] ?? (throw const NotFoundException('Servizio non trovato.'));

  ChangeRequest changeRequest(String id) =>
      changeRequests[id] ??
      (throw const NotFoundException('Richiesta di modifica non trovata.'));

  DocumentInfo document(String id) =>
      documents[id] ??
      (throw const NotFoundException('Documento non trovato.'));

  ServiceType serviceType(String id) =>
      serviceTypes[id] ??
      (throw const NotFoundException('Tipologia di servizio non trovata.'));

  Patient patient(String id) =>
      patients[id] ?? (throw const NotFoundException('Paziente non trovato.'));

  String operatorName(String? id) =>
      id == null ? 'Non assegnato' : (operators[id]?.fullName ?? id);

  static void checkVersion(int current, int expected) {
    if (current != expected) throw const ConcurrencyConflictException();
  }

  // ---------------------------------------------------------------------------
  // Registro attività e notifiche
  // ---------------------------------------------------------------------------

  AuditEntry audit({
    required String action,
    required AuditEntityType entityType,
    required String entityId,
    required String entityLabel,
    required String summary,
    List<FieldChange> changes = const [],
    String? serviceId,
    ActorKind actorKind = ActorKind.centrale,
    String? actorName,
    String? actorId,
    DateTime? at,
  }) {
    final entry = AuditEntry(
      id: newId('aud'),
      occurredAt: at ?? now,
      actorKind: actorKind,
      actorName:
          actorName ??
          (actorKind == ActorKind.centrale
              ? currentUser.displayName
              : 'Sistema PeopleCare'),
      actorId:
          actorId ??
          (actorKind == ActorKind.centrale && actorName == null
              ? currentUser.id
              : null),
      action: action,
      entityType: entityType,
      entityId: entityId,
      entityLabel: entityLabel,
      summary: summary,
      changes: changes,
      serviceId: serviceId,
    );
    auditLog.add(entry);
    return entry;
  }

  AppNotification notify({
    required NotificationType type,
    required NotificationSeverity severity,
    required String title,
    required String message,
    String? serviceId,
    String? operatorId,
    String? changeRequestId,
    String? documentId,
    DateTime? at,
    DateTime? readAt,
    bool live = true,
  }) {
    final notification = AppNotification(
      id: newId('ntf'),
      type: type,
      severity: severity,
      title: title,
      message: message,
      createdAt: at ?? now,
      readAt: readAt,
      serviceId: serviceId,
      operatorId: operatorId,
      changeRequestId: changeRequestId,
      documentId: documentId,
    );
    notifications.add(notification);
    if (live) {
      if (!_newNotifications.isClosed) _newNotifications.add(notification);
      emit(OperationalEventTopic.notifiche, notification.id);
    }
    return notification;
  }

  // ---------------------------------------------------------------------------
  // Strutture e tipologie
  // ---------------------------------------------------------------------------

  void _validateFacility(FacilityDraft draft) {
    final errors = <String, String>{};
    if (draft.name.trim().isEmpty) errors['name'] = 'Indica il nome.';
    if (draft.address.trim().isEmpty) {
      errors['address'] = 'Indica l\'indirizzo.';
    }
    if (draft.city.trim().isEmpty) errors['city'] = 'Indica il comune.';
    final email = emptyToNull(draft.email);
    if (email != null && !isValidEmail(email)) {
      errors['email'] = 'Email non valida.';
    }
    final duplicate = facilities.values.any(
      (f) => normalizeForSearch(f.name) == normalizeForSearch(draft.name),
    );
    if (duplicate) errors['name'] = 'Esiste già una struttura con questo nome.';
    if (errors.isNotEmpty) {
      throw ValidationException(
        'Controlla i dati della struttura.',
        fieldErrors: errors,
      );
    }
  }

  Facility createFacility(FacilityDraft draft) {
    _validateFacility(draft);
    final facility = Facility(
      id: newId('str'),
      code: 'STR-${(nextFacilityNumber++).toString().padLeft(2, '0')}',
      name: draft.name.trim(),
      kind: draft.kind,
      address: draft.address.trim(),
      city: draft.city.trim(),
      phone: emptyToNull(draft.phone),
      email: emptyToNull(draft.email),
      isActive: draft.isActive,
      notes: emptyToNull(draft.notes),
    );
    facilities[facility.id] = facility;
    audit(
      action: AuditActions.facilityCreated,
      entityType: AuditEntityType.struttura,
      entityId: facility.id,
      entityLabel: facility.name,
      summary: 'Creata la struttura ${facility.name} (${facility.code}).',
    );
    emit(OperationalEventTopic.strutture, facility.id);
    return facility;
  }

  Facility updateFacility(String id, FacilityDraft draft, int expectedVersion) {
    final current = facility(id);
    checkVersion(current.version, expectedVersion);
    final others = Map.of(facilities)..remove(id);
    final errors = <String, String>{};
    if (draft.name.trim().isEmpty) errors['name'] = 'Indica il nome.';
    if (others.values.any(
      (f) => normalizeForSearch(f.name) == normalizeForSearch(draft.name),
    )) {
      errors['name'] = 'Esiste già una struttura con questo nome.';
    }
    if (draft.address.trim().isEmpty) {
      errors['address'] = 'Indica l\'indirizzo.';
    }
    if (draft.city.trim().isEmpty) errors['city'] = 'Indica il comune.';
    final email = emptyToNull(draft.email);
    if (email != null && !isValidEmail(email)) {
      errors['email'] = 'Email non valida.';
    }
    if (errors.isNotEmpty) {
      throw ValidationException(
        'Controlla i dati della struttura.',
        fieldErrors: errors,
      );
    }
    final updated = current.copyWith(
      name: draft.name.trim(),
      kind: draft.kind,
      address: draft.address.trim(),
      city: draft.city.trim(),
      phone: emptyToNull(draft.phone),
      email: email,
      isActive: draft.isActive,
      notes: emptyToNull(draft.notes),
      version: current.version + 1,
    );
    facilities[id] = updated;
    final changes = [
      ?_change('name', 'Nome', current.name, updated.name),
      ?_change('kind', 'Tipologia', current.kind.code, updated.kind.code),
      ?_change(
        'address',
        'Indirizzo',
        current.fullAddress,
        updated.fullAddress,
      ),
      ?_change('phone', 'Telefono', current.phone, updated.phone),
      ?_change('email', 'Email', current.email, updated.email),
      ?_change(
        'is_active',
        'Attiva',
        current.isActive ? 'Sì' : 'No',
        updated.isActive ? 'Sì' : 'No',
      ),
      ?_change('notes', 'Note', current.notes, updated.notes),
    ];
    audit(
      action: AuditActions.facilityUpdated,
      entityType: AuditEntityType.struttura,
      entityId: id,
      entityLabel: updated.name,
      summary: 'Modificata la struttura ${updated.name}.',
      changes: changes,
    );
    emit(OperationalEventTopic.strutture, id);
    return updated;
  }

  void _validateServiceType(ServiceTypeDraft draft, {String? excludeId}) {
    final errors = <String, String>{};
    if (draft.name.trim().isEmpty) errors['name'] = 'Indica il nome.';
    if (draft.category.trim().isEmpty) errors['category'] = 'Indica l\'area.';
    if (draft.defaultDurationMinutes < 5 ||
        draft.defaultDurationMinutes > ServicePolicy.maxDuration.inMinutes) {
      errors['default_duration_minutes'] =
          'Durata tra 5 minuti e ${ServicePolicy.maxDuration.inHours} ore.';
    }
    final duplicate = serviceTypes.values.any(
      (t) =>
          t.id != excludeId &&
          normalizeForSearch(t.name) == normalizeForSearch(draft.name),
    );
    if (duplicate) errors['name'] = 'Esiste già una tipologia con questo nome.';
    final unknown = draft.requiredQualifications.where(
      (q) => !qualifications.contains(q),
    );
    if (unknown.isNotEmpty) {
      errors['required_qualifications'] =
          'Qualifiche non riconosciute: ${unknown.join(', ')}.';
    }
    if (errors.isNotEmpty) {
      throw ValidationException(
        'Controlla i dati della tipologia.',
        fieldErrors: errors,
      );
    }
  }

  ServiceType createServiceType(ServiceTypeDraft draft) {
    _validateServiceType(draft);
    final type = ServiceType(
      id: newId('tip'),
      code: 'TS-${(nextServiceTypeNumber++).toString().padLeft(2, '0')}',
      name: draft.name.trim(),
      category: draft.category.trim(),
      defaultDurationMinutes: draft.defaultDurationMinutes,
      requiredQualifications: List.unmodifiable(draft.requiredQualifications),
      description: emptyToNull(draft.description),
      isActive: draft.isActive,
    );
    serviceTypes[type.id] = type;
    audit(
      action: AuditActions.serviceTypeCreated,
      entityType: AuditEntityType.tipologiaServizio,
      entityId: type.id,
      entityLabel: type.name,
      summary: 'Aggiunta al catalogo la tipologia ${type.name} (${type.code}).',
    );
    emit(OperationalEventTopic.tipologieServizio, type.id);
    return type;
  }

  ServiceType updateServiceType(
    String id,
    ServiceTypeDraft draft,
    int expectedVersion,
  ) {
    final current = serviceType(id);
    checkVersion(current.version, expectedVersion);
    _validateServiceType(draft, excludeId: id);
    final updated = ServiceType(
      id: id,
      code: current.code,
      name: draft.name.trim(),
      category: draft.category.trim(),
      defaultDurationMinutes: draft.defaultDurationMinutes,
      requiredQualifications: List.unmodifiable(draft.requiredQualifications),
      description: emptyToNull(draft.description),
      isActive: draft.isActive,
      version: current.version + 1,
    );
    serviceTypes[id] = updated;
    audit(
      action: AuditActions.serviceTypeUpdated,
      entityType: AuditEntityType.tipologiaServizio,
      entityId: id,
      entityLabel: updated.name,
      summary: 'Modificata la tipologia ${updated.name}.',
      changes: [
        ?_change('name', 'Nome', current.name, updated.name),
        ?_change('category', 'Area', current.category, updated.category),
        ?_change(
          'default_duration_minutes',
          'Durata predefinita',
          '${current.defaultDurationMinutes} min',
          '${updated.defaultDurationMinutes} min',
        ),
        ?_change(
          'required_qualifications',
          'Qualifiche richieste',
          current.requiredQualifications.join(', '),
          updated.requiredQualifications.join(', '),
        ),
        ?_change(
          'is_active',
          'Attiva',
          current.isActive ? 'Sì' : 'No',
          updated.isActive ? 'Sì' : 'No',
        ),
      ],
    );
    emit(OperationalEventTopic.tipologieServizio, id);
    return updated;
  }

  // ---------------------------------------------------------------------------
  // Operatori
  // ---------------------------------------------------------------------------

  List<String> _cleanSecondary(OperatorDraft draft) {
    final seen = <String>{draft.primaryFacilityId};
    return [
      for (final id in draft.secondaryFacilityIds)
        if (seen.add(id)) id,
    ];
  }

  void _validateOperator(OperatorDraft draft, {String? excludeId}) {
    final errors = <String, String>{};
    if (draft.firstName.trim().isEmpty) {
      errors['first_name'] = 'Indica il nome.';
    }
    if (draft.lastName.trim().isEmpty) {
      errors['last_name'] = 'Indica il cognome.';
    }
    if (!isValidEmail(draft.email.trim())) {
      errors['email'] = 'Email non valida.';
    } else if (operators.values.any(
      (o) =>
          o.id != excludeId &&
          o.email.toLowerCase() == draft.email.trim().toLowerCase(),
    )) {
      errors['email'] = 'Email già usata da un altro operatore.';
    }
    if (!isValidPhone(draft.phone)) errors['phone'] = 'Telefono non valido.';
    if (draft.qualification.trim().isEmpty) {
      errors['qualification'] = 'Indica la qualifica.';
    }
    if (!facilities.containsKey(draft.primaryFacilityId)) {
      errors['primary_facility_id'] = 'Seleziona la struttura principale.';
    }
    for (final id in draft.secondaryFacilityIds) {
      if (!facilities.containsKey(id)) {
        errors['secondary_facility_ids'] = 'Struttura aggiuntiva non valida.';
      }
    }
    if (errors.isNotEmpty) {
      throw ValidationException(
        'Controlla i dati dell\'operatore.',
        fieldErrors: errors,
      );
    }
  }

  Operator createOperator(OperatorDraft draft) {
    _validateOperator(draft);
    final at = now;
    final operator = Operator(
      id: newId('opr'),
      code: 'OP-${(nextOperatorNumber++).toString().padLeft(6, '0')}',
      firstName: draft.firstName.trim(),
      lastName: draft.lastName.trim(),
      email: draft.email.trim(),
      phone: draft.phone.trim(),
      qualification: draft.qualification.trim(),
      primaryFacilityId: draft.primaryFacilityId,
      secondaryFacilityIds: _cleanSecondary(draft),
      notes: emptyToNull(draft.notes),
      createdAt: at,
      updatedAt: at,
    );
    operators[operator.id] = operator;
    if (!qualifications.contains(operator.qualification)) {
      qualifications.add(operator.qualification);
    }
    audit(
      action: AuditActions.operatorCreated,
      entityType: AuditEntityType.operatore,
      entityId: operator.id,
      entityLabel: operator.fullName,
      summary: 'Creato l\'operatore ${operator.fullName} (${operator.code}).',
    );
    emit(OperationalEventTopic.operatori, operator.id);
    return operator;
  }

  Operator updateOperator(String id, OperatorDraft draft, int expectedVersion) {
    final current = operator(id);
    checkVersion(current.version, expectedVersion);
    _validateOperator(draft, excludeId: id);
    final updated = current.copyWith(
      firstName: draft.firstName.trim(),
      lastName: draft.lastName.trim(),
      email: draft.email.trim(),
      phone: draft.phone.trim(),
      qualification: draft.qualification.trim(),
      primaryFacilityId: draft.primaryFacilityId,
      secondaryFacilityIds: _cleanSecondary(draft),
      notes: emptyToNull(draft.notes),
      updatedAt: now,
      version: current.version + 1,
    );
    operators[id] = updated;
    String facilityNames(List<String> ids) =>
        ids.map((f) => facilities[f]?.name ?? f).join(', ');
    audit(
      action: AuditActions.operatorUpdated,
      entityType: AuditEntityType.operatore,
      entityId: id,
      entityLabel: updated.fullName,
      summary: 'Modificati i dati dell\'operatore ${updated.fullName}.',
      changes: [
        ?_change('first_name', 'Nome', current.firstName, updated.firstName),
        ?_change('last_name', 'Cognome', current.lastName, updated.lastName),
        ?_change('email', 'Email', current.email, updated.email),
        ?_change('phone', 'Telefono', current.phone, updated.phone),
        ?_change(
          'qualification',
          'Qualifica',
          current.qualification,
          updated.qualification,
        ),
        ?_change(
          'primary_facility_id',
          'Struttura principale',
          facilityNames([current.primaryFacilityId]),
          facilityNames([updated.primaryFacilityId]),
        ),
        ?_change(
          'secondary_facility_ids',
          'Strutture aggiuntive',
          facilityNames(current.secondaryFacilityIds),
          facilityNames(updated.secondaryFacilityIds),
        ),
        ?_change('notes', 'Note', current.notes, updated.notes),
      ],
    );
    emit(OperationalEventTopic.operatori, id);
    return updated;
  }

  Operator changeOperatorStatus(
    String id,
    OperatorStatus status,
    String? reason,
    int expectedVersion,
  ) {
    final current = operator(id);
    checkVersion(current.version, expectedVersion);
    if (current.status == status) return current;
    if (status != OperatorStatus.attivo && emptyToNull(reason) == null) {
      throw const ValidationException(
        'Indica il motivo della sospensione o disabilitazione.',
        fieldErrors: {'reason': 'Motivo obbligatorio.'},
      );
    }
    final updated = current.copyWith(
      status: status,
      statusReason: status == OperatorStatus.attivo ? null : reason!.trim(),
      updatedAt: now,
      version: current.version + 1,
    );
    operators[id] = updated;
    audit(
      action: AuditActions.operatorStatusChanged,
      entityType: AuditEntityType.operatore,
      entityId: id,
      entityLabel: updated.fullName,
      summary:
          'Stato di ${updated.fullName}: ${_operatorStatusLabel(status)}'
          '${status == OperatorStatus.attivo ? '' : ' (${updated.statusReason})'}.',
      changes: [
        ?_change(
          'status',
          'Stato',
          _operatorStatusLabel(current.status),
          _operatorStatusLabel(status),
        ),
      ],
    );
    if (status != OperatorStatus.attivo) {
      final upcoming = services.values
          .where(
            (s) =>
                s.operatorId == id &&
                s.scheduledEnd.isAfter(now) &&
                !s.status.isFinal,
          )
          .length;
      if (upcoming > 0) {
        notify(
          type: NotificationType.operativa,
          severity: NotificationSeverity.attenzione,
          title: 'Servizi da riassegnare',
          message:
              '${updated.fullName} è ${_operatorStatusLabel(status).toLowerCase()} '
              'ma ha $upcoming servizi futuri assegnati.',
          operatorId: id,
        );
      }
    }
    emit(OperationalEventTopic.operatori, id);
    return updated;
  }

  Operator linkAccount(String id, String username, int expectedVersion) {
    final current = operator(id);
    checkVersion(current.version, expectedVersion);
    final clean = username.trim().toLowerCase();
    if (!isValidEmail(clean)) {
      throw const ValidationException(
        'Indica un nome utente valido (email aziendale).',
        fieldErrors: {'username': 'Nome utente non valido.'},
      );
    }
    final usedBy = operators.values.where(
      (o) => o.id != id && o.account?.username == clean,
    );
    if (usedBy.isNotEmpty) {
      throw ValidationException(
        'Account già collegato a ${usedBy.first.fullName}.',
        fieldErrors: const {'username': 'Account già collegato.'},
      );
    }
    final updated = current.copyWith(
      account: OperatorAccount(
        accountId: newId('acc'),
        username: clean,
        status: AccountStatus.invitato,
        linkedAt: now,
      ),
      updatedAt: now,
      version: current.version + 1,
    );
    operators[id] = updated;
    audit(
      action: AuditActions.operatorAccountLinked,
      entityType: AuditEntityType.operatore,
      entityId: id,
      entityLabel: updated.fullName,
      summary:
          'Collegato l\'account $clean a ${updated.fullName} (invito inviato).',
      changes: [
        ?_change('account', 'Account', current.account?.username, clean),
      ],
    );
    emit(OperationalEventTopic.operatori, id);
    return updated;
  }

  Operator unlinkAccount(String id, int expectedVersion) {
    final current = operator(id);
    checkVersion(current.version, expectedVersion);
    if (current.account == null) return current;
    final updated = current.copyWith(
      account: null,
      updatedAt: now,
      version: current.version + 1,
    );
    operators[id] = updated;
    audit(
      action: AuditActions.operatorAccountUnlinked,
      entityType: AuditEntityType.operatore,
      entityId: id,
      entityLabel: updated.fullName,
      summary:
          'Scollegato l\'account ${current.account!.username} da ${updated.fullName}.',
      changes: [
        ?_change('account', 'Account', current.account!.username, null),
      ],
    );
    emit(OperationalEventTopic.operatori, id);
    return updated;
  }

  // ---------------------------------------------------------------------------
  // Servizi
  // ---------------------------------------------------------------------------

  void _validateServiceDraft(ServiceDraft draft, {Service? existing}) {
    final errors = <String, String>{};
    switch (draft.kind) {
      case CatalogServiceKind(:final serviceTypeId):
        final type = serviceTypes[serviceTypeId];
        if (type == null) {
          errors['service_type_id'] = 'Tipologia non presente nel catalogo.';
        } else if (!type.isActive && existing?.serviceTypeId != serviceTypeId) {
          errors['service_type_id'] = 'La tipologia ${type.name} non è attiva.';
        }
      case CustomServiceKind(:final name):
        if (name.trim().isEmpty) {
          errors['custom_type_name'] = 'Descrivi il servizio personalizzato.';
        }
    }
    final scheduleError = ServicePolicy.validateSchedule(
      draft.scheduledStart,
      draft.scheduledEnd,
    );
    if (scheduleError != null) errors['scheduled_end'] = scheduleError;
    switch (draft.patient) {
      case RegisteredServicePatient(:final patientId):
        if (!patients.containsKey(patientId)) {
          errors['patient'] = 'Paziente non trovato.';
        }
      case ManualServicePatient(:final firstName, :final lastName):
        if (firstName.trim().isEmpty || lastName.trim().isEmpty) {
          errors['patient'] = 'Indica nome e cognome del paziente.';
        }
    }
    final facility = facilities[draft.facilityId];
    if (facility == null) {
      errors['facility_id'] = 'Seleziona la struttura.';
    } else if (!facility.isActive && existing?.facilityId != draft.facilityId) {
      errors['facility_id'] = 'La struttura ${facility.name} non è attiva.';
    }
    final operatorId = draft.operatorId;
    if (operatorId != null) {
      final operator = operators[operatorId];
      if (operator == null) {
        errors['operator_id'] = 'Operatore non trovato.';
      } else if (!operator.isAssignable && existing?.operatorId != operatorId) {
        errors['operator_id'] =
            '${operator.fullName} è ${_operatorStatusLabel(operator.status).toLowerCase()} '
            'e non può ricevere servizi.';
      }
    }
    if (draft.address.trim().isEmpty) {
      errors['address'] = 'Indica l\'indirizzo.';
    }
    final phone = emptyToNull(draft.phone);
    if (phone != null && !isValidPhone(phone)) {
      errors['phone'] = 'Telefono non valido.';
    }
    if (errors.isNotEmpty) {
      throw ValidationException(
        'Controlla i dati del servizio.',
        fieldErrors: errors,
      );
    }
  }

  ServicePatient _normalizePatient(ServicePatient patient) => switch (patient) {
    RegisteredServicePatient(:final patientId) => RegisteredServicePatient(
      patientId: patientId,
      firstName: patients[patientId]!.firstName,
      lastName: patients[patientId]!.lastName,
    ),
    ManualServicePatient(:final firstName, :final lastName) =>
      ManualServicePatient(
        firstName: firstName.trim(),
        lastName: lastName.trim(),
      ),
  };

  ServiceKind _normalizeKind(ServiceKind kind) => switch (kind) {
    CatalogServiceKind(:final serviceTypeId) => CatalogServiceKind(
      serviceTypeId: serviceTypeId,
      name: serviceTypes[serviceTypeId]!.name,
    ),
    CustomServiceKind(:final name) => CustomServiceKind(name.trim()),
  };

  String nextServiceCode(DateTime at) =>
      'SRV-${at.year}-${(nextServiceNumber++).toString().padLeft(6, '0')}';

  Service createService(
    ServiceDraft draft, {
    DateTime? at,
    String? createdBy,
    bool live = true,
  }) {
    _validateServiceDraft(draft);
    final created = at ?? now;
    final author = createdBy ?? currentUser.displayName;
    final service = Service(
      id: newId('srv'),
      code: nextServiceCode(created),
      kind: _normalizeKind(draft.kind),
      facilityId: draft.facilityId,
      operatorId: draft.operatorId,
      patient: _normalizePatient(draft.patient),
      scheduledStart: draft.scheduledStart,
      scheduledEnd: draft.scheduledEnd,
      status: draft.operatorId == null
          ? ServiceStatus.daAssegnare
          : ServiceStatus.assegnato,
      priority: draft.priority,
      address: draft.address.trim(),
      phone: emptyToNull(draft.phone),
      directions: emptyToNull(draft.directions),
      notes: emptyToNull(draft.notes),
      createdAt: created,
      createdBy: author,
      updatedAt: created,
      updatedBy: author,
    );
    services[service.id] = service;
    audit(
      action: AuditActions.serviceCreated,
      entityType: AuditEntityType.servizio,
      entityId: service.id,
      entityLabel: service.code,
      serviceId: service.id,
      actorName: createdBy,
      at: created,
      summary:
          'Creato il servizio ${service.kind.label} per ${service.patient.fullName} '
          'del ${formatDateTime(service.scheduledStart)}'
          '${service.operatorId == null ? ', da assegnare' : ', assegnato a ${operatorName(service.operatorId)}'}.',
    );
    if (live) emit(OperationalEventTopic.servizi, service.id);
    return service;
  }

  Service updateService(String id, ServiceDraft draft, int expectedVersion) {
    final current = service(id);
    checkVersion(current.version, expectedVersion);
    if (!ServicePolicy.canEdit(current)) {
      throw OperationNotAllowedException(
        'Il servizio è ${_serviceStatusLabel(current.status).toLowerCase()}: '
        'non è più modificabile.',
      );
    }
    _validateServiceDraft(draft, existing: current);
    final scheduleChanged =
        draft.scheduledStart != current.scheduledStart ||
        draft.scheduledEnd != current.scheduledEnd;
    final status = ServicePolicy.statusAfterUpdate(
      current: current.status,
      operatorId: draft.operatorId,
      scheduleChanged: scheduleChanged,
    );
    final updated = current.copyWith(
      kind: _normalizeKind(draft.kind),
      facilityId: draft.facilityId,
      operatorId: draft.operatorId,
      patient: _normalizePatient(draft.patient),
      scheduledStart: draft.scheduledStart,
      scheduledEnd: draft.scheduledEnd,
      status: status,
      statusReason: status == ServiceStatus.daRiprogrammare
          ? current.statusReason
          : null,
      priority: draft.priority,
      address: draft.address.trim(),
      phone: emptyToNull(draft.phone),
      directions: emptyToNull(draft.directions),
      notes: emptyToNull(draft.notes),
      updatedAt: now,
      updatedBy: currentUser.displayName,
      version: current.version + 1,
    );
    services[id] = updated;
    final changes = _serviceChanges(current, updated);
    audit(
      action: AuditActions.serviceUpdated,
      entityType: AuditEntityType.servizio,
      entityId: id,
      entityLabel: updated.code,
      serviceId: id,
      summary: changes.isEmpty
          ? 'Servizio salvato senza modifiche.'
          : 'Modificato il servizio (${changes.map((c) => c.label.toLowerCase()).join(', ')}).',
      changes: changes,
    );
    emit(OperationalEventTopic.servizi, id);
    return updated;
  }

  Service rescheduleService(
    String id, {
    required DateTime start,
    required DateTime end,
    String? reason,
    required int expectedVersion,
  }) {
    final current = service(id);
    checkVersion(current.version, expectedVersion);
    if (!ServicePolicy.canReschedule(current)) {
      throw OperationNotAllowedException(
        'Non è possibile riprogrammare un servizio '
        '${_serviceStatusLabel(current.status).toLowerCase()}.',
      );
    }
    final error = ServicePolicy.validateSchedule(start, end);
    if (error != null) {
      throw ValidationException(error, fieldErrors: {'scheduled_end': error});
    }
    final updated = current.copyWith(
      scheduledStart: start,
      scheduledEnd: end,
      status: ServicePolicy.statusAfterReschedule(
        operatorId: current.operatorId,
      ),
      statusReason: null,
      updatedAt: now,
      updatedBy: currentUser.displayName,
      version: current.version + 1,
    );
    services[id] = updated;
    audit(
      action: AuditActions.serviceRescheduled,
      entityType: AuditEntityType.servizio,
      entityId: id,
      entityLabel: updated.code,
      serviceId: id,
      summary:
          'Riprogrammato dal ${formatDateTime(current.scheduledStart)} '
          'al ${formatDateTime(start)}'
          '${emptyToNull(reason) == null ? '' : ' - motivo: ${reason!.trim()}'}.',
      changes: _serviceChanges(current, updated),
    );
    emit(OperationalEventTopic.servizi, id);
    return updated;
  }

  Service reassignService(
    String id, {
    required String? operatorId,
    String? reason,
    required int expectedVersion,
  }) {
    final current = service(id);
    checkVersion(current.version, expectedVersion);
    if (!ServicePolicy.canReassign(current)) {
      throw OperationNotAllowedException(
        'Non è possibile riassegnare un servizio '
        '${_serviceStatusLabel(current.status).toLowerCase()}.',
      );
    }
    if (operatorId != null) {
      final target = operator(operatorId);
      if (!target.isAssignable) {
        throw OperationNotAllowedException(
          '${target.fullName} è ${_operatorStatusLabel(target.status).toLowerCase()} '
          'e non può ricevere servizi.',
        );
      }
    }
    if (current.operatorId == operatorId) return current;
    final updated = current.copyWith(
      operatorId: operatorId,
      status: ServicePolicy.statusAfterReassign(
        current: current.status,
        operatorId: operatorId,
      ),
      updatedAt: now,
      updatedBy: currentUser.displayName,
      version: current.version + 1,
    );
    services[id] = updated;
    audit(
      action: AuditActions.serviceReassigned,
      entityType: AuditEntityType.servizio,
      entityId: id,
      entityLabel: updated.code,
      serviceId: id,
      summary: operatorId == null
          ? 'Rimossa l\'assegnazione a ${operatorName(current.operatorId)}.'
          : 'Assegnato a ${operatorName(operatorId)}'
                '${current.operatorId == null ? '' : ' (prima: ${operatorName(current.operatorId)})'}'
                '${emptyToNull(reason) == null ? '' : ' - motivo: ${reason!.trim()}'}.',
      changes: _serviceChanges(current, updated),
    );
    emit(OperationalEventTopic.servizi, id);
    return updated;
  }

  Service cancelService(String id, String reason, int expectedVersion) {
    final current = service(id);
    checkVersion(current.version, expectedVersion);
    if (!ServicePolicy.canCancel(current)) {
      throw OperationNotAllowedException(
        'Non è possibile annullare un servizio '
        '${_serviceStatusLabel(current.status).toLowerCase()}.',
      );
    }
    if (emptyToNull(reason) == null) {
      throw const ValidationException(
        'Indica il motivo dell\'annullamento.',
        fieldErrors: {'reason': 'Motivo obbligatorio.'},
      );
    }
    final updated = current.copyWith(
      status: ServiceStatus.annullato,
      statusReason: reason.trim(),
      updatedAt: now,
      updatedBy: currentUser.displayName,
      version: current.version + 1,
    );
    services[id] = updated;
    audit(
      action: AuditActions.serviceCancelled,
      entityType: AuditEntityType.servizio,
      entityId: id,
      entityLabel: updated.code,
      serviceId: id,
      summary: 'Servizio annullato - motivo: ${reason.trim()}.',
      changes: _serviceChanges(current, updated),
    );
    emit(OperationalEventTopic.servizi, id);
    return updated;
  }

  Service markToReschedule(String id, String reason, int expectedVersion) {
    final current = service(id);
    checkVersion(current.version, expectedVersion);
    if (!ServicePolicy.canMarkToReschedule(current)) {
      throw OperationNotAllowedException(
        'Un servizio ${_serviceStatusLabel(current.status).toLowerCase()} '
        'non può essere segnato da riprogrammare.',
      );
    }
    if (emptyToNull(reason) == null) {
      throw const ValidationException(
        'Indica il motivo.',
        fieldErrors: {'reason': 'Motivo obbligatorio.'},
      );
    }
    final updated = current.copyWith(
      status: ServiceStatus.daRiprogrammare,
      statusReason: reason.trim(),
      updatedAt: now,
      updatedBy: currentUser.displayName,
      version: current.version + 1,
    );
    services[id] = updated;
    audit(
      action: AuditActions.serviceMarkedToReschedule,
      entityType: AuditEntityType.servizio,
      entityId: id,
      entityLabel: updated.code,
      serviceId: id,
      summary: 'Servizio da riprogrammare - motivo: ${reason.trim()}.',
      changes: _serviceChanges(current, updated),
    );
    emit(OperationalEventTopic.servizi, id);
    return updated;
  }

  void deleteService(String id, int expectedVersion) {
    final current = service(id);
    checkVersion(current.version, expectedVersion);
    final blocked = ServicePolicy.deleteBlockedReason(current);
    if (blocked != null) throw OperationNotAllowedException(blocked);
    services.remove(id);
    audit(
      action: AuditActions.serviceDeleted,
      entityType: AuditEntityType.servizio,
      entityId: id,
      entityLabel: current.code,
      serviceId: id,
      summary:
          'Eliminato il servizio ${current.kind.label} per '
          '${current.patient.fullName} del ${formatDateTime(current.scheduledStart)}.',
    );
    emit(OperationalEventTopic.servizi, id);
  }

  List<FieldChange> _serviceChanges(Service before, Service after) {
    String patientLabel(ServicePatient p) =>
        p is ManualServicePatient ? '${p.fullName} (dati manuali)' : p.fullName;
    String kindLabel(ServiceKind k) =>
        k is CustomServiceKind ? '${k.name} (personalizzato)' : k.label;
    return [
      ?_change(
        'service_type',
        'Tipologia',
        kindLabel(before.kind),
        kindLabel(after.kind),
      ),
      ?_change(
        'scheduled_start',
        'Inizio programmato',
        formatDateTime(before.scheduledStart),
        formatDateTime(after.scheduledStart),
      ),
      ?_change(
        'scheduled_end',
        'Fine programmata',
        formatDateTime(before.scheduledEnd),
        formatDateTime(after.scheduledEnd),
      ),
      ?_change(
        'patient',
        'Paziente',
        patientLabel(before.patient),
        patientLabel(after.patient),
      ),
      ?_change(
        'facility_id',
        'Struttura',
        facilities[before.facilityId]?.name,
        facilities[after.facilityId]?.name,
      ),
      ?_change(
        'operator_id',
        'Operatore',
        operatorName(before.operatorId),
        operatorName(after.operatorId),
      ),
      ?_change(
        'priority',
        'Priorità',
        _priorityLabel(before.priority),
        _priorityLabel(after.priority),
      ),
      ?_change('address', 'Indirizzo', before.address, after.address),
      ?_change('phone', 'Telefono', before.phone, after.phone),
      ?_change(
        'directions',
        'Indicazioni',
        before.directions,
        after.directions,
      ),
      ?_change('notes', 'Note', before.notes, after.notes),
      ?_change(
        'status',
        'Stato',
        _serviceStatusLabel(before.status),
        _serviceStatusLabel(after.status),
      ),
    ];
  }

  /// Ricalcola i contatori derivati del servizio (senza cambiare versione).
  void refreshServiceCounters(String serviceId) {
    final current = services[serviceId];
    if (current == null) return;
    final documentCount = documents.values
        .where(
          (d) =>
              d.owner.type == DocumentOwnerType.servizio &&
              d.owner.id == serviceId,
        )
        .length;
    final openRequests = changeRequests.values
        .where((r) => r.serviceId == serviceId && r.status.isOpen)
        .length;
    services[serviceId] = current.copyWith(
      documentCount: documentCount,
      openChangeRequestCount: openRequests,
    );
  }

  // ---------------------------------------------------------------------------
  // Azioni dell'app mobile (simulate)
  // ---------------------------------------------------------------------------

  /// L'operatore avvia il servizio dall'app mobile.
  Service startServiceFromMobile(
    String id,
    DateTime at, {
    bool live = true,
    bool withNotification = true,
  }) {
    final current = service(id);
    if (current.status != ServiceStatus.assegnato) return current;
    final updated = current.copyWith(
      status: ServiceStatus.inCorso,
      actualStart: at,
      updatedAt: at,
      updatedBy: operatorName(current.operatorId),
      version: current.version + 1,
    );
    services[id] = updated;
    final startedBy = operatorName(current.operatorId);
    audit(
      action: AuditActions.serviceStarted,
      entityType: AuditEntityType.servizio,
      entityId: id,
      entityLabel: updated.code,
      serviceId: id,
      actorKind: ActorKind.operatore,
      actorName: startedBy,
      actorId: current.operatorId,
      at: at,
      summary: 'Servizio avviato dall\'app mobile alle ${formatTime(at)}.',
      changes: [
        ?_change('actual_start', 'Inizio effettivo', null, formatDateTime(at)),
        ?_change(
          'status',
          'Stato',
          _serviceStatusLabel(current.status),
          _serviceStatusLabel(updated.status),
        ),
      ],
    );
    if (withNotification) {
      notify(
        type: NotificationType.servizioIniziato,
        severity: NotificationSeverity.info,
        title: 'Servizio iniziato',
        message:
            '$startedBy ha iniziato ${updated.kind.label} presso '
            '${updated.patient.fullName} alle ${formatTime(at)}.',
        serviceId: id,
        operatorId: current.operatorId,
        at: at,
        live: live,
      );
    }
    if (live) emit(OperationalEventTopic.servizi, id);
    return updated;
  }

  /// L'operatore termina il servizio dall'app mobile.
  Service completeServiceFromMobile(
    String id,
    DateTime at, {
    bool live = true,
    bool withNotification = true,
  }) {
    final current = service(id);
    if (current.status != ServiceStatus.inCorso) return current;
    final updated = current.copyWith(
      status: ServiceStatus.completato,
      actualEnd: at,
      updatedAt: at,
      updatedBy: operatorName(current.operatorId),
      version: current.version + 1,
    );
    services[id] = updated;
    final name = operatorName(current.operatorId);
    final minutes = updated.actualDuration?.inMinutes ?? 0;
    audit(
      action: AuditActions.serviceCompleted,
      entityType: AuditEntityType.servizio,
      entityId: id,
      entityLabel: updated.code,
      serviceId: id,
      actorKind: ActorKind.operatore,
      actorName: name,
      actorId: current.operatorId,
      at: at,
      summary:
          'Servizio terminato dall\'app mobile alle ${formatTime(at)} '
          '(durata effettiva $minutes min).',
      changes: [
        ?_change('actual_end', 'Fine effettiva', null, formatDateTime(at)),
        ?_change(
          'status',
          'Stato',
          _serviceStatusLabel(current.status),
          _serviceStatusLabel(updated.status),
        ),
      ],
    );
    if (withNotification) {
      notify(
        type: NotificationType.servizioTerminato,
        severity: NotificationSeverity.info,
        title: 'Servizio terminato',
        message:
            '$name ha terminato ${updated.kind.label} presso '
            '${updated.patient.fullName} ($minutes min).',
        serviceId: id,
        operatorId: current.operatorId,
        at: at,
        live: live,
      );
    }
    if (live) emit(OperationalEventTopic.servizi, id);
    return updated;
  }

  /// L'operatore segnala che il servizio non è stato eseguito.
  Service markNotExecutedFromMobile(
    String id,
    DateTime at,
    String reason, {
    bool live = true,
    bool withNotification = true,
  }) {
    final current = service(id);
    if (current.status != ServiceStatus.assegnato &&
        current.status != ServiceStatus.inCorso) {
      return current;
    }
    final updated = current.copyWith(
      status: ServiceStatus.nonEseguito,
      statusReason: reason,
      updatedAt: at,
      updatedBy: operatorName(current.operatorId),
      version: current.version + 1,
    );
    services[id] = updated;
    final name = operatorName(current.operatorId);
    audit(
      action: AuditActions.serviceNotExecuted,
      entityType: AuditEntityType.servizio,
      entityId: id,
      entityLabel: updated.code,
      serviceId: id,
      actorKind: ActorKind.operatore,
      actorName: name,
      actorId: current.operatorId,
      at: at,
      summary: 'Servizio non eseguito - motivo: $reason.',
      changes: [
        ?_change(
          'status',
          'Stato',
          _serviceStatusLabel(current.status),
          _serviceStatusLabel(updated.status),
        ),
      ],
    );
    if (withNotification) {
      notify(
        type: NotificationType.servizioProblematico,
        severity: NotificationSeverity.attenzione,
        title: 'Servizio non eseguito',
        message:
            '${updated.code} - ${updated.patient.fullName}: $reason '
            '(segnalato da $name).',
        serviceId: id,
        operatorId: current.operatorId,
        at: at,
        live: live,
      );
    }
    if (live) emit(OperationalEventTopic.servizi, id);
    return updated;
  }

  /// Notifica di avvio in ritardo (generata dal sistema).
  void notifyLateStart(Service service, {DateTime? at, bool live = true}) {
    if (!lateNotifiedServiceIds.add(service.id)) return;
    final when = at ?? now;
    final minutes = when.difference(service.scheduledStart).inMinutes;
    notify(
      type: NotificationType.servizioProblematico,
      severity: minutes > 30
          ? NotificationSeverity.critica
          : NotificationSeverity.attenzione,
      title: 'Servizio non ancora avviato',
      message:
          '${service.code} - ${service.patient.fullName}: '
          '${operatorName(service.operatorId)} non ha ancora avviato il servizio '
          'previsto alle ${formatTime(service.scheduledStart)} ($minutes min di ritardo).',
      serviceId: service.id,
      operatorId: service.operatorId,
      at: when,
      live: live,
    );
  }

  /// L'operatore invia una richiesta di modifica dall'app mobile.
  ChangeRequest submitChangeRequestFromMobile({
    required String serviceId,
    required ChangeRequestReason reason,
    required String message,
    DateTime? proposedStart,
    DateTime? proposedEnd,
    required DateTime at,
    bool live = true,
  }) {
    final target = service(serviceId);
    final operatorId = target.operatorId;
    if (operatorId == null) {
      throw const OperationNotAllowedException(
        'Solo l\'operatore assegnato può chiedere una modifica.',
      );
    }
    final operator = this.operator(operatorId);
    final request = ChangeRequest(
      id: newId('rm'),
      code: 'RM-${(nextChangeRequestNumber++).toString().padLeft(6, '0')}',
      serviceId: serviceId,
      serviceCode: target.code,
      operatorId: operatorId,
      operatorName: operator.fullName,
      reason: reason,
      message: message,
      proposedStart: proposedStart,
      proposedEnd: proposedEnd,
      status: ChangeRequestStatus.inAttesa,
      createdAt: at,
      updatedAt: at,
    );
    changeRequests[request.id] = request;
    refreshServiceCounters(serviceId);
    audit(
      action: AuditActions.changeRequestReceived,
      entityType: AuditEntityType.richiestaModifica,
      entityId: request.id,
      entityLabel: request.code,
      serviceId: serviceId,
      actorKind: ActorKind.operatore,
      actorName: operator.fullName,
      actorId: operator.id,
      at: at,
      summary:
          'Richiesta di modifica ${request.code} su ${target.code} '
          '(${_reasonLabel(reason)}).',
    );
    notify(
      type: NotificationType.richiestaModifica,
      severity: target.scheduledStart.difference(at).inHours < 24
          ? NotificationSeverity.attenzione
          : NotificationSeverity.info,
      title: 'Nuova richiesta di modifica',
      message:
          '${operator.fullName} - ${_reasonLabel(reason)} su ${target.code} '
          '(${formatDateTime(target.scheduledStart)}).',
      serviceId: serviceId,
      operatorId: operator.id,
      changeRequestId: request.id,
      at: at,
      live: live,
    );
    if (live) {
      emit(OperationalEventTopic.richiesteModifica, request.id);
      emit(OperationalEventTopic.servizi, serviceId);
    }
    return request;
  }

  /// Documento inviato dall'operatore dall'app mobile.
  DocumentInfo receiveDocumentFromMobile({
    required DocumentOwner owner,
    required String operatorId,
    required String title,
    required String fileName,
    required DocumentCategory category,
    required int sizeBytes,
    required DateTime at,
    String? description,
    bool live = true,
  }) {
    final sender = operator(operatorId);
    final document = DocumentInfo(
      id: newId('doc'),
      title: title,
      fileName: fileName,
      mimeType: mimeTypeFor(fileName),
      sizeBytes: sizeBytes,
      category: category,
      owner: DocumentOwner(
        type: owner.type,
        id: owner.id,
        label: ownerLabel(owner.type, owner.id),
      ),
      source: DocumentSource.operatore,
      uploadedBy: sender.fullName,
      uploadedAt: at,
      description: description,
      requiresReview: true,
    );
    documents[document.id] = document;
    final serviceId = owner.type == DocumentOwnerType.servizio
        ? owner.id
        : null;
    if (serviceId != null) refreshServiceCounters(serviceId);
    audit(
      action: AuditActions.documentReceived,
      entityType: AuditEntityType.documento,
      entityId: document.id,
      entityLabel: document.title,
      serviceId: serviceId,
      actorKind: ActorKind.operatore,
      actorName: sender.fullName,
      actorId: sender.id,
      at: at,
      summary:
          'Ricevuto il documento "${document.title}" '
          '(${document.owner.label}) dall\'app mobile.',
    );
    notify(
      type: NotificationType.documentoRicevuto,
      severity: NotificationSeverity.info,
      title: 'Documento ricevuto',
      message:
          '${sender.fullName} ha inviato "${document.title}" '
          'per ${document.owner.label}.',
      serviceId: serviceId,
      operatorId: sender.id,
      documentId: document.id,
      at: at,
      live: live,
    );
    if (live) {
      emit(OperationalEventTopic.documenti, document.id);
      if (serviceId != null) emit(OperationalEventTopic.servizi, serviceId);
    }
    return document;
  }

  // ---------------------------------------------------------------------------
  // Richieste di modifica (Centrale)
  // ---------------------------------------------------------------------------

  ChangeRequest replyToChangeRequest(
    String id,
    String message,
    int expectedVersion,
  ) {
    final current = changeRequest(id);
    checkVersion(current.version, expectedVersion);
    if (!current.status.isOpen) {
      throw const OperationNotAllowedException('La richiesta è già chiusa.');
    }
    final text = emptyToNull(message);
    if (text == null) {
      throw const ValidationException(
        'Scrivi il messaggio per l\'operatore.',
        fieldErrors: {'message': 'Messaggio obbligatorio.'},
      );
    }
    final updated = current.copyWith(
      status: ChangeRequestStatus.inLavorazione,
      updatedAt: now,
      messages: [
        ...current.messages,
        ChangeRequestMessage(
          id: newId('msg'),
          authorKind: ActorKind.centrale,
          authorName: currentUser.displayName,
          text: text,
          sentAt: now,
        ),
      ],
      version: current.version + 1,
    );
    changeRequests[id] = updated;
    audit(
      action: AuditActions.changeRequestReplied,
      entityType: AuditEntityType.richiestaModifica,
      entityId: id,
      entityLabel: updated.code,
      serviceId: updated.serviceId,
      summary: 'Risposta inviata a ${updated.operatorName}: "$text".',
    );
    emit(OperationalEventTopic.richiesteModifica, id);
    return updated;
  }

  ChangeRequest resolveChangeRequest(
    String id,
    ChangeRequestResolution resolution,
    int expectedVersion,
  ) {
    final current = changeRequest(id);
    checkVersion(current.version, expectedVersion);
    if (!current.status.isOpen) {
      throw const OperationNotAllowedException('La richiesta è già chiusa.');
    }
    final target = service(current.serviceId);
    final origin = 'Richiesta di modifica ${current.code}';
    String decision;
    switch (resolution) {
      case RescheduleResolution(:final start, :final end):
        final updated = rescheduleService(
          target.id,
          start: start,
          end: end,
          reason: origin,
          expectedVersion: target.version,
        );
        decision =
            'orario modificato: ${formatDateTime(updated.scheduledStart)}'
            '-${formatTime(updated.scheduledEnd)}';
      case ReassignResolution(:final operatorId):
        reassignService(
          target.id,
          operatorId: operatorId,
          reason: origin,
          expectedVersion: target.version,
        );
        decision = 'riassegnato a ${operatorName(operatorId)}';
      case KeepAssignmentResolution():
        decision = 'assegnazione mantenuta';
    }
    final text = emptyToNull(resolution.message);
    final updated = current.copyWith(
      status: ChangeRequestStatus.chiusa,
      outcome: resolution.outcome,
      closedAt: now,
      closedBy: currentUser.displayName,
      updatedAt: now,
      messages: [
        ...current.messages,
        if (text != null)
          ChangeRequestMessage(
            id: newId('msg'),
            authorKind: ActorKind.centrale,
            authorName: currentUser.displayName,
            text: text,
            sentAt: now,
          ),
      ],
      version: current.version + 1,
    );
    changeRequests[id] = updated;
    refreshServiceCounters(current.serviceId);
    audit(
      action: AuditActions.changeRequestClosed,
      entityType: AuditEntityType.richiestaModifica,
      entityId: id,
      entityLabel: updated.code,
      serviceId: updated.serviceId,
      summary: 'Richiesta ${updated.code} chiusa: $decision.',
    );
    emit(OperationalEventTopic.richiesteModifica, id);
    emit(OperationalEventTopic.servizi, current.serviceId);
    return updated;
  }

  // ---------------------------------------------------------------------------
  // Documenti (Centrale)
  // ---------------------------------------------------------------------------

  String ownerLabel(DocumentOwnerType type, String? id) {
    switch (type) {
      case DocumentOwnerType.centrale:
        return 'Centrale Operativa';
      case DocumentOwnerType.servizio:
        final s = services[id];
        return s == null
            ? 'Servizio eliminato'
            : '${s.code} - ${s.patient.fullName}';
      case DocumentOwnerType.operatore:
        final o = operators[id];
        return o == null ? 'Operatore' : '${o.fullName} (${o.code})';
      case DocumentOwnerType.paziente:
        final p = patients[id];
        return p == null ? 'Paziente' : '${p.fullName} (${p.code})';
    }
  }

  DocumentInfo uploadDocument(DocumentUpload upload) {
    final owner = upload.owner;
    final exists = switch (owner.type) {
      DocumentOwnerType.centrale => true,
      DocumentOwnerType.servizio => services.containsKey(owner.id),
      DocumentOwnerType.operatore => operators.containsKey(owner.id),
      DocumentOwnerType.paziente => patients.containsKey(owner.id),
    };
    if (!exists) {
      throw const NotFoundException(
        'L\'elemento a cui associare il documento non esiste.',
      );
    }
    if (upload.bytes.isEmpty) {
      throw const ValidationException('Il file è vuoto.');
    }
    if (upload.bytes.length > maxUploadBytes) {
      throw const ValidationException(
        'Il file supera la dimensione massima di 20 MB.',
      );
    }
    final title = emptyToNull(upload.title) ?? upload.fileName;
    final document = DocumentInfo(
      id: newId('doc'),
      title: title,
      fileName: upload.fileName,
      mimeType: upload.mimeType,
      sizeBytes: upload.bytes.length,
      category: upload.category,
      owner: DocumentOwner(
        type: owner.type,
        id: owner.type == DocumentOwnerType.centrale ? null : owner.id,
        label: ownerLabel(owner.type, owner.id),
      ),
      source: DocumentSource.centrale,
      uploadedBy: currentUser.displayName,
      uploadedAt: now,
      description: emptyToNull(upload.description),
    );
    documents[document.id] = document;
    documentContents[document.id] = upload.bytes;
    final serviceId = owner.type == DocumentOwnerType.servizio
        ? owner.id
        : null;
    if (serviceId != null) refreshServiceCounters(serviceId);
    audit(
      action: AuditActions.documentUploaded,
      entityType: AuditEntityType.documento,
      entityId: document.id,
      entityLabel: document.title,
      serviceId: serviceId,
      summary:
          'Caricato il documento "${document.title}" (${document.owner.label}).',
    );
    emit(OperationalEventTopic.documenti, document.id);
    if (serviceId != null) emit(OperationalEventTopic.servizi, serviceId);
    return document;
  }

  DocumentContent downloadDocument(String id) {
    final info = document(id);
    final bytes =
        documentContents[id] ??
        buildDemoPdf(
          title: info.title,
          lines: [
            'Categoria: ${info.category.code}',
            'Associato a: ${info.owner.label}',
            'Caricato da: ${info.uploadedBy} il ${formatDateTime(info.uploadedAt)}',
            '',
            'Questo file e\' generato dall\'archivio dimostrativo.',
            'Nessun dato reale e\' contenuto in questo documento.',
          ],
        );
    final fileName = documentContents.containsKey(id)
        ? info.fileName
        : (info.extension == 'pdf' ? info.fileName : '${info.fileName}.pdf');
    return DocumentContent(
      fileName: fileName,
      mimeType: documentContents.containsKey(id)
          ? info.mimeType
          : 'application/pdf',
      bytes: bytes,
    );
  }

  DocumentInfo markDocumentReviewed(String id) {
    final current = document(id);
    if (!current.isPendingReview) return current;
    final updated = current.copyWith(
      reviewedAt: now,
      reviewedBy: currentUser.displayName,
    );
    documents[id] = updated;
    audit(
      action: AuditActions.documentReviewed,
      entityType: AuditEntityType.documento,
      entityId: id,
      entityLabel: updated.title,
      serviceId: updated.owner.type == DocumentOwnerType.servizio
          ? updated.owner.id
          : null,
      summary: 'Verificato il documento "${updated.title}".',
    );
    emit(OperationalEventTopic.documenti, id);
    return updated;
  }

  void deleteDocument(String id) {
    final current = document(id);
    if (current.source != DocumentSource.centrale) {
      throw const OperationNotAllowedException(
        'I documenti ricevuti dal territorio non possono essere eliminati.',
      );
    }
    documents.remove(id);
    documentContents.remove(id);
    final serviceId = current.owner.type == DocumentOwnerType.servizio
        ? current.owner.id
        : null;
    if (serviceId != null) refreshServiceCounters(serviceId);
    audit(
      action: AuditActions.documentDeleted,
      entityType: AuditEntityType.documento,
      entityId: id,
      entityLabel: current.title,
      serviceId: serviceId,
      summary:
          'Eliminato il documento "${current.title}" (${current.owner.label}).',
    );
    emit(OperationalEventTopic.documenti, id);
    if (serviceId != null) emit(OperationalEventTopic.servizi, serviceId);
  }

  // ---------------------------------------------------------------------------
  // Notifiche
  // ---------------------------------------------------------------------------

  void markNotificationRead(String id) {
    final index = notifications.indexWhere((n) => n.id == id);
    if (index < 0) throw const NotFoundException('Notifica non trovata.');
    if (notifications[index].isRead) return;
    notifications[index] = notifications[index].markRead(now);
    emit(OperationalEventTopic.notifiche, id);
  }

  void markAllNotificationsRead() {
    final at = now;
    var changed = false;
    for (var i = 0; i < notifications.length; i++) {
      if (!notifications[i].isRead) {
        notifications[i] = notifications[i].markRead(at);
        changed = true;
      }
    }
    if (changed) emit(OperationalEventTopic.notifiche);
  }
}

// -----------------------------------------------------------------------------
// Utilità condivise dal mock
// -----------------------------------------------------------------------------

FieldChange? _change(
  String field,
  String label,
  String? before,
  String? after,
) {
  final a = emptyToNull(before);
  final b = emptyToNull(after);
  if (a == b) return null;
  return FieldChange(field: field, label: label, oldValue: a, newValue: b);
}

String _two(int value) => value.toString().padLeft(2, '0');

String formatDateTime(DateTime value) =>
    '${_two(value.day)}/${_two(value.month)}/${value.year} ${formatTime(value)}';

String formatTime(DateTime value) =>
    '${_two(value.hour)}:${_two(value.minute)}';

bool isValidEmail(String value) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());

bool isValidPhone(String value) {
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  return RegExp(r'^\+?[0-9 ./-]+$').hasMatch(value.trim()) &&
      digits.length >= 6 &&
      digits.length <= 15;
}

String mimeTypeFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final extension = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  return switch (extension) {
    'pdf' => 'application/pdf',
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'txt' => 'text/plain',
    'csv' => 'text/csv',
    _ => 'application/octet-stream',
  };
}

String _serviceStatusLabel(ServiceStatus status) => switch (status) {
  ServiceStatus.daAssegnare => 'Da assegnare',
  ServiceStatus.assegnato => 'Assegnato',
  ServiceStatus.inCorso => 'In corso',
  ServiceStatus.completato => 'Completato',
  ServiceStatus.annullato => 'Annullato',
  ServiceStatus.nonEseguito => 'Non eseguito',
  ServiceStatus.daRiprogrammare => 'Da riprogrammare',
};

String _operatorStatusLabel(OperatorStatus status) => switch (status) {
  OperatorStatus.attivo => 'Attivo',
  OperatorStatus.sospeso => 'Sospeso',
  OperatorStatus.disabilitato => 'Disabilitato',
};

String _priorityLabel(ServicePriority priority) => switch (priority) {
  ServicePriority.bassa => 'Bassa',
  ServicePriority.normale => 'Normale',
  ServicePriority.alta => 'Alta',
  ServicePriority.urgente => 'Urgente',
};

String _reasonLabel(ChangeRequestReason reason) => switch (reason) {
  ChangeRequestReason.problemaOrario => 'problema di orario',
  ChangeRequestReason.sovrapposizione => 'sovrapposizione',
  ChangeRequestReason.indisponibilita => 'indisponibilità',
  ChangeRequestReason.problemaLogistico => 'problema logistico',
  ChangeRequestReason.imprevisto => 'imprevisto',
  ChangeRequestReason.altro => 'altro',
};

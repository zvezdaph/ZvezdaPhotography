import '../../domain/domain.dart';
import 'json_reader.dart';

/// Conversione JSON <-> entità secondo API_CONTRACT.md.
///
/// Questi codec non sono usati dal mock (che lavora in memoria): sono pronti
/// per l'implementazione HTTP dei repository e sono verificati dai test sugli
/// esempi del contratto (`test/fixtures/api`).

// -----------------------------------------------------------------------------
// Utente, strutture, tipologie, pazienti
// -----------------------------------------------------------------------------

CentralUser centralUserFromJson(JsonMap json) => CentralUser(
  id: json.string('id'),
  displayName: json.string('display_name'),
  role: json.string('role'),
  facilityIds: json.stringList('facility_ids'),
);

JsonMap centralUserToJson(CentralUser user) => {
  'id': user.id,
  'display_name': user.displayName,
  'role': user.role,
  'facility_ids': user.facilityIds,
};

Facility facilityFromJson(JsonMap json) => Facility(
  id: json.string('id'),
  code: json.string('code'),
  name: json.string('name'),
  kind: FacilityKind.fromCode(json.string('kind')),
  address: json.string('address'),
  city: json.string('city'),
  phone: json.optString('phone'),
  email: json.optString('email'),
  isActive: json.optBoolean('is_active', fallback: true),
  notes: json.optString('notes'),
  version: json.integer('version'),
);

JsonMap facilityToJson(Facility facility) => {
  'id': facility.id,
  'code': facility.code,
  'name': facility.name,
  'kind': facility.kind.code,
  'address': facility.address,
  'city': facility.city,
  'phone': facility.phone,
  'email': facility.email,
  'is_active': facility.isActive,
  'notes': facility.notes,
  'version': facility.version,
};

JsonMap facilityDraftToJson(FacilityDraft draft, {int? expectedVersion}) => {
  'name': draft.name,
  'kind': draft.kind.code,
  'address': draft.address,
  'city': draft.city,
  'phone': draft.phone,
  'email': draft.email,
  'is_active': draft.isActive,
  'notes': draft.notes,
  'expected_version': ?expectedVersion,
};

ServiceType serviceTypeFromJson(JsonMap json) => ServiceType(
  id: json.string('id'),
  code: json.string('code'),
  name: json.string('name'),
  category: json.string('category'),
  defaultDurationMinutes: json.integer('default_duration_minutes'),
  requiredQualifications: json.stringList('required_qualifications'),
  description: json.optString('description'),
  isActive: json.optBoolean('is_active', fallback: true),
  version: json.integer('version'),
);

JsonMap serviceTypeToJson(ServiceType type) => {
  'id': type.id,
  'code': type.code,
  'name': type.name,
  'category': type.category,
  'default_duration_minutes': type.defaultDurationMinutes,
  'required_qualifications': type.requiredQualifications,
  'description': type.description,
  'is_active': type.isActive,
  'version': type.version,
};

JsonMap serviceTypeDraftToJson(
  ServiceTypeDraft draft, {
  int? expectedVersion,
}) => {
  'name': draft.name,
  'category': draft.category,
  'default_duration_minutes': draft.defaultDurationMinutes,
  'required_qualifications': draft.requiredQualifications,
  'description': draft.description,
  'is_active': draft.isActive,
  'expected_version': ?expectedVersion,
};

Patient patientFromJson(JsonMap json) => Patient(
  id: json.string('id'),
  code: json.string('code'),
  firstName: json.string('first_name'),
  lastName: json.string('last_name'),
  birthDate: json.optDate('birth_date'),
  address: json.optString('address'),
  city: json.optString('city'),
  phone: json.optString('phone'),
  facilityId: json.optString('facility_id'),
  notes: json.optString('notes'),
);

JsonMap patientToJson(Patient patient) => {
  'id': patient.id,
  'code': patient.code,
  'first_name': patient.firstName,
  'last_name': patient.lastName,
  'birth_date': patient.birthDate == null
      ? null
      : formatDate(patient.birthDate!),
  'address': patient.address,
  'city': patient.city,
  'phone': patient.phone,
  'facility_id': patient.facilityId,
  'notes': patient.notes,
};

// -----------------------------------------------------------------------------
// Operatori
// -----------------------------------------------------------------------------

OperatorAccount operatorAccountFromJson(JsonMap json) => OperatorAccount(
  accountId: json.string('account_id'),
  username: json.string('username'),
  status: AccountStatus.fromCode(json.string('status')),
  linkedAt: json.optTimestamp('linked_at'),
);

JsonMap operatorAccountToJson(OperatorAccount account) => {
  'account_id': account.accountId,
  'username': account.username,
  'status': account.status.code,
  'linked_at': account.linkedAt == null
      ? null
      : formatTimestamp(account.linkedAt!),
};

Operator operatorFromJson(JsonMap json) {
  final account = json.optObject('account');
  return Operator(
    id: json.string('id'),
    code: json.string('code'),
    firstName: json.string('first_name'),
    lastName: json.string('last_name'),
    email: json.string('email'),
    phone: json.string('phone'),
    qualification: json.string('qualification'),
    primaryFacilityId: json.string('primary_facility_id'),
    secondaryFacilityIds: json.stringList('secondary_facility_ids'),
    status: OperatorStatus.fromCode(json.string('status')),
    statusReason: json.optString('status_reason'),
    account: account == null ? null : operatorAccountFromJson(account),
    lastAccessAt: json.optTimestamp('last_access_at'),
    notes: json.optString('notes'),
    createdAt: json.timestamp('created_at'),
    updatedAt: json.timestamp('updated_at'),
    version: json.integer('version'),
  );
}

JsonMap operatorToJson(Operator operator) => {
  'id': operator.id,
  'code': operator.code,
  'first_name': operator.firstName,
  'last_name': operator.lastName,
  'email': operator.email,
  'phone': operator.phone,
  'qualification': operator.qualification,
  'primary_facility_id': operator.primaryFacilityId,
  'secondary_facility_ids': operator.secondaryFacilityIds,
  'status': operator.status.code,
  'status_reason': operator.statusReason,
  'account': operator.account == null
      ? null
      : operatorAccountToJson(operator.account!),
  'last_access_at': operator.lastAccessAt == null
      ? null
      : formatTimestamp(operator.lastAccessAt!),
  'notes': operator.notes,
  'created_at': formatTimestamp(operator.createdAt),
  'updated_at': formatTimestamp(operator.updatedAt),
  'version': operator.version,
};

JsonMap operatorDraftToJson(OperatorDraft draft, {int? expectedVersion}) => {
  'first_name': draft.firstName,
  'last_name': draft.lastName,
  'email': draft.email,
  'phone': draft.phone,
  'qualification': draft.qualification,
  'primary_facility_id': draft.primaryFacilityId,
  'secondary_facility_ids': draft.secondaryFacilityIds,
  'notes': draft.notes,
  'expected_version': ?expectedVersion,
};

// -----------------------------------------------------------------------------
// Servizi
// -----------------------------------------------------------------------------

ServiceKind _serviceKindFromJson(JsonMap json) {
  final type = json.optObject('service_type');
  if (type != null) {
    return CatalogServiceKind(
      serviceTypeId: type.string('id'),
      name: type.string('name'),
    );
  }
  final custom = json.optString('custom_type_name');
  if (custom == null) {
    throw const FormatException(
      'Servizio senza "service_type" né "custom_type_name"',
    );
  }
  return CustomServiceKind(custom);
}

ServicePatient _servicePatientFromJson(JsonMap json) {
  final id = json.optString('id');
  final firstName = json.string('first_name');
  final lastName = json.string('last_name');
  return id == null
      ? ManualServicePatient(firstName: firstName, lastName: lastName)
      : RegisteredServicePatient(
          patientId: id,
          firstName: firstName,
          lastName: lastName,
        );
}

Service serviceFromJson(JsonMap json) => Service(
  id: json.string('id'),
  code: json.string('code'),
  kind: _serviceKindFromJson(json),
  facilityId: json.string('facility_id'),
  operatorId: json.optString('operator_id'),
  patient: _servicePatientFromJson(json.object('patient')),
  scheduledStart: json.timestamp('scheduled_start'),
  scheduledEnd: json.timestamp('scheduled_end'),
  actualStart: json.optTimestamp('actual_start'),
  actualEnd: json.optTimestamp('actual_end'),
  status: ServiceStatus.fromCode(json.string('status')),
  priority: ServicePriority.fromCode(json.string('priority')),
  address: json.string('address'),
  phone: json.optString('phone'),
  directions: json.optString('directions'),
  notes: json.optString('notes'),
  statusReason: json.optString('status_reason'),
  documentCount: json.optInteger('document_count') ?? 0,
  openChangeRequestCount: json.optInteger('open_change_request_count') ?? 0,
  createdAt: json.timestamp('created_at'),
  createdBy: json.string('created_by'),
  updatedAt: json.timestamp('updated_at'),
  updatedBy: json.string('updated_by'),
  version: json.integer('version'),
);

JsonMap serviceToJson(Service service) => {
  'id': service.id,
  'code': service.code,
  'service_type': switch (service.kind) {
    CatalogServiceKind(:final serviceTypeId, :final name) => {
      'id': serviceTypeId,
      'name': name,
    },
    CustomServiceKind() => null,
  },
  'custom_type_name': switch (service.kind) {
    CustomServiceKind(:final name) => name,
    CatalogServiceKind() => null,
  },
  'facility_id': service.facilityId,
  'operator_id': service.operatorId,
  'patient': {
    'id': service.patient.patientId,
    'first_name': service.patient.firstName,
    'last_name': service.patient.lastName,
  },
  'scheduled_start': formatTimestamp(service.scheduledStart),
  'scheduled_end': formatTimestamp(service.scheduledEnd),
  'actual_start': service.actualStart == null
      ? null
      : formatTimestamp(service.actualStart!),
  'actual_end': service.actualEnd == null
      ? null
      : formatTimestamp(service.actualEnd!),
  'status': service.status.code,
  'priority': service.priority.code,
  'address': service.address,
  'phone': service.phone,
  'directions': service.directions,
  'notes': service.notes,
  'status_reason': service.statusReason,
  'document_count': service.documentCount,
  'open_change_request_count': service.openChangeRequestCount,
  'created_at': formatTimestamp(service.createdAt),
  'created_by': service.createdBy,
  'updated_at': formatTimestamp(service.updatedAt),
  'updated_by': service.updatedBy,
  'version': service.version,
};

/// Corpo di `POST /services` e `PUT /services/{id}`.
JsonMap serviceDraftToJson(ServiceDraft draft, {int? expectedVersion}) => {
  'service_type_id': switch (draft.kind) {
    CatalogServiceKind(:final serviceTypeId) => serviceTypeId,
    CustomServiceKind() => null,
  },
  'custom_type_name': switch (draft.kind) {
    CustomServiceKind(:final name) => name,
    CatalogServiceKind() => null,
  },
  'scheduled_start': formatTimestamp(draft.scheduledStart),
  'scheduled_end': formatTimestamp(draft.scheduledEnd),
  'patient_id': draft.patient.patientId,
  'manual_patient': switch (draft.patient) {
    ManualServicePatient(:final firstName, :final lastName) => {
      'first_name': firstName,
      'last_name': lastName,
    },
    RegisteredServicePatient() => null,
  },
  'facility_id': draft.facilityId,
  'operator_id': draft.operatorId,
  'priority': draft.priority.code,
  'address': draft.address,
  'phone': draft.phone,
  'directions': draft.directions,
  'notes': draft.notes,
  'expected_version': ?expectedVersion,
};

// -----------------------------------------------------------------------------
// Richieste di modifica
// -----------------------------------------------------------------------------

ChangeRequestMessage changeRequestMessageFromJson(JsonMap json) =>
    ChangeRequestMessage(
      id: json.string('id'),
      authorKind: ActorKind.fromCode(json.string('author_kind')),
      authorName: json.string('author_name'),
      text: json.string('text'),
      sentAt: json.timestamp('sent_at'),
    );

JsonMap changeRequestMessageToJson(ChangeRequestMessage message) => {
  'id': message.id,
  'author_kind': message.authorKind.code,
  'author_name': message.authorName,
  'text': message.text,
  'sent_at': formatTimestamp(message.sentAt),
};

ChangeRequest changeRequestFromJson(JsonMap json) {
  final outcome = json.optString('outcome');
  return ChangeRequest(
    id: json.string('id'),
    code: json.string('code'),
    serviceId: json.string('service_id'),
    serviceCode: json.string('service_code'),
    operatorId: json.string('operator_id'),
    operatorName: json.string('operator_name'),
    reason: ChangeRequestReason.fromCode(json.string('reason')),
    message: json.string('message'),
    proposedStart: json.optTimestamp('proposed_start'),
    proposedEnd: json.optTimestamp('proposed_end'),
    status: ChangeRequestStatus.fromCode(json.string('status')),
    createdAt: json.timestamp('created_at'),
    updatedAt: json.timestamp('updated_at'),
    messages: json.objectList('messages', changeRequestMessageFromJson),
    outcome: outcome == null ? null : ChangeRequestOutcome.fromCode(outcome),
    closedAt: json.optTimestamp('closed_at'),
    closedBy: json.optString('closed_by'),
    version: json.integer('version'),
  );
}

JsonMap changeRequestToJson(ChangeRequest request) => {
  'id': request.id,
  'code': request.code,
  'service_id': request.serviceId,
  'service_code': request.serviceCode,
  'operator_id': request.operatorId,
  'operator_name': request.operatorName,
  'reason': request.reason.code,
  'message': request.message,
  'proposed_start': request.proposedStart == null
      ? null
      : formatTimestamp(request.proposedStart!),
  'proposed_end': request.proposedEnd == null
      ? null
      : formatTimestamp(request.proposedEnd!),
  'status': request.status.code,
  'created_at': formatTimestamp(request.createdAt),
  'updated_at': formatTimestamp(request.updatedAt),
  'messages': [
    for (final message in request.messages) changeRequestMessageToJson(message),
  ],
  'outcome': request.outcome?.code,
  'closed_at': request.closedAt == null
      ? null
      : formatTimestamp(request.closedAt!),
  'closed_by': request.closedBy,
  'version': request.version,
};

/// Corpo di `POST /change-requests/{id}/resolve`.
JsonMap changeRequestResolutionToJson(
  ChangeRequestResolution resolution, {
  required int expectedVersion,
}) => {
  'expected_version': expectedVersion,
  'outcome': resolution.outcome.code,
  ...switch (resolution) {
    RescheduleResolution(:final start, :final end) => {
      'scheduled_start': formatTimestamp(start),
      'scheduled_end': formatTimestamp(end),
    },
    ReassignResolution(:final operatorId) => {'operator_id': operatorId},
    KeepAssignmentResolution() => const <String, Object?>{},
  },
  'message': resolution.message,
};

// -----------------------------------------------------------------------------
// Documenti
// -----------------------------------------------------------------------------

DocumentInfo documentFromJson(JsonMap json) {
  final owner = json.object('owner');
  return DocumentInfo(
    id: json.string('id'),
    title: json.string('title'),
    fileName: json.string('file_name'),
    mimeType: json.string('mime_type'),
    sizeBytes: json.integer('size_bytes'),
    category: DocumentCategory.fromCode(json.string('category')),
    owner: DocumentOwner(
      type: DocumentOwnerType.fromCode(owner.string('type')),
      id: owner.optString('id'),
      label: owner.optString('label') ?? '',
    ),
    source: DocumentSource.fromCode(json.string('source')),
    uploadedBy: json.string('uploaded_by'),
    uploadedAt: json.timestamp('uploaded_at'),
    description: json.optString('description'),
    requiresReview: json.optBoolean('requires_review'),
    reviewedAt: json.optTimestamp('reviewed_at'),
    reviewedBy: json.optString('reviewed_by'),
  );
}

JsonMap documentToJson(DocumentInfo document) => {
  'id': document.id,
  'title': document.title,
  'file_name': document.fileName,
  'mime_type': document.mimeType,
  'size_bytes': document.sizeBytes,
  'category': document.category.code,
  'owner': {
    'type': document.owner.type.code,
    'id': document.owner.id,
    'label': document.owner.label,
  },
  'source': document.source.code,
  'uploaded_by': document.uploadedBy,
  'uploaded_at': formatTimestamp(document.uploadedAt),
  'description': document.description,
  'requires_review': document.requiresReview,
  'reviewed_at': document.reviewedAt == null
      ? null
      : formatTimestamp(document.reviewedAt!),
  'reviewed_by': document.reviewedBy,
};

/// Campi testuali della richiesta multipart `POST /documents` (il file va
/// nella parte `file`).
Map<String, String> documentUploadFields(DocumentUpload upload) => {
  'owner_type': upload.owner.type.code,
  if (upload.owner.id != null) 'owner_id': upload.owner.id!,
  'title': upload.title,
  'category': upload.category.code,
  if (upload.description != null) 'description': upload.description!,
};

// -----------------------------------------------------------------------------
// Notifiche, audit, eventi
// -----------------------------------------------------------------------------

AppNotification notificationFromJson(JsonMap json) => AppNotification(
  id: json.string('id'),
  type: NotificationType.fromCode(json.string('type')),
  severity: NotificationSeverity.fromCode(json.string('severity')),
  title: json.string('title'),
  message: json.string('message'),
  createdAt: json.timestamp('created_at'),
  readAt: json.optTimestamp('read_at'),
  serviceId: json.optString('service_id'),
  operatorId: json.optString('operator_id'),
  changeRequestId: json.optString('change_request_id'),
  documentId: json.optString('document_id'),
);

JsonMap notificationToJson(AppNotification notification) => {
  'id': notification.id,
  'type': notification.type.code,
  'severity': notification.severity.code,
  'title': notification.title,
  'message': notification.message,
  'created_at': formatTimestamp(notification.createdAt),
  'read_at': notification.readAt == null
      ? null
      : formatTimestamp(notification.readAt!),
  'service_id': notification.serviceId,
  'operator_id': notification.operatorId,
  'change_request_id': notification.changeRequestId,
  'document_id': notification.documentId,
};

AuditEntry auditEntryFromJson(JsonMap json) {
  final actor = json.object('actor');
  final entity = json.object('entity');
  return AuditEntry(
    id: json.string('id'),
    occurredAt: json.timestamp('occurred_at'),
    actorKind: ActorKind.fromCode(actor.string('kind')),
    actorName: actor.string('name'),
    actorId: actor.optString('id'),
    action: json.string('action'),
    entityType: AuditEntityType.fromCode(entity.string('type')),
    entityId: entity.string('id'),
    entityLabel: entity.string('label'),
    summary: json.string('summary'),
    changes: json.objectList(
      'changes',
      (change) => FieldChange(
        field: change.string('field'),
        label: change.string('label'),
        oldValue: change.optString('old_value'),
        newValue: change.optString('new_value'),
      ),
    ),
    serviceId: json.optString('service_id'),
  );
}

JsonMap auditEntryToJson(AuditEntry entry) => {
  'id': entry.id,
  'occurred_at': formatTimestamp(entry.occurredAt),
  'actor': {
    'kind': entry.actorKind.code,
    'name': entry.actorName,
    'id': entry.actorId,
  },
  'action': entry.action,
  'entity': {
    'type': entry.entityType.code,
    'id': entry.entityId,
    'label': entry.entityLabel,
  },
  'summary': entry.summary,
  'changes': [
    for (final change in entry.changes)
      {
        'field': change.field,
        'label': change.label,
        'old_value': change.oldValue,
        'new_value': change.newValue,
      },
  ],
  'service_id': entry.serviceId,
};

/// Evento del canale in tempo reale; `null` per argomenti sconosciuti (da
/// ignorare, per compatibilità con versioni future del sistema).
OperationalEvent? operationalEventFromJson(JsonMap json) {
  final topic = OperationalEventTopic.tryFromCode(json.string('topic'));
  if (topic == null) return null;
  return OperationalEvent(
    topic: topic,
    entityId: json.optString('entity_id'),
    occurredAt: json.timestamp('occurred_at'),
  );
}

JsonMap operationalEventToJson(OperationalEvent event) => {
  'topic': event.topic.code,
  'entity_id': event.entityId,
  'occurred_at': formatTimestamp(event.occurredAt),
};

PagedResult<T> pagedResultFromJson<T>(
  JsonMap json,
  T Function(JsonMap json) decode,
) => PagedResult<T>(
  items: json.objectList('items', decode),
  total: json.integer('total'),
  page: json.integer('page'),
  pageSize: json.integer('page_size'),
);

// -----------------------------------------------------------------------------
// Report
// -----------------------------------------------------------------------------

Map<ServiceStatus, int> _statusCounts(JsonMap json) => {
  for (final status in ServiceStatus.values)
    status: json.optInteger(status.code) ?? 0,
};

JsonMap _statusCountsToJson(Map<ServiceStatus, int> counts) => {
  for (final status in ServiceStatus.values) status.code: counts[status] ?? 0,
};

OperationalReport operationalReportFromJson(JsonMap json) {
  final period = json.object('period');
  final requests = json.optObject('change_requests_by_reason') ?? const {};
  return OperationalReport(
    period: DateRange(period.timestamp('from'), period.timestamp('to')),
    facilityId: json.optString('facility_id'),
    generatedAt: json.timestamp('generated_at'),
    totalServices: json.integer('total_services'),
    byStatus: _statusCounts(json.object('by_status')),
    startedServices: json.integer('started_services'),
    onTimeStarts: json.integer('on_time_starts'),
    onTimeToleranceMinutes: json.integer('on_time_tolerance_minutes'),
    averageStartDelayMinutes: json.optNumber('average_start_delay_minutes'),
    scheduledMinutes: json.integer('scheduled_minutes'),
    deliveredMinutes: json.integer('delivered_minutes'),
    changeRequestCount: json.integer('change_request_count'),
    changeRequestsByReason: {
      for (final reason in ChangeRequestReason.values)
        reason: requests.optInteger(reason.code) ?? 0,
    },
    daily: json.objectList(
      'daily',
      (day) => DailyServiceStat(
        day: day.optDate('date')!,
        byStatus: _statusCounts(day.object('by_status')),
      ),
    ),
    operators: json.objectList(
      'operators',
      (row) => OperatorReportRow(
        operatorId: row.string('operator_id'),
        operatorName: row.string('operator_name'),
        operatorCode: row.string('operator_code'),
        totalServices: row.integer('total_services'),
        completed: row.integer('completed'),
        notExecuted: row.integer('not_executed'),
        cancelled: row.integer('cancelled'),
        scheduledMinutes: row.integer('scheduled_minutes'),
        deliveredMinutes: row.integer('delivered_minutes'),
        averageStartDelayMinutes: row.optNumber('average_start_delay_minutes'),
      ),
    ),
    serviceTypes: json.objectList(
      'service_types',
      (row) => ServiceTypeReportRow(
        label: row.string('label'),
        serviceTypeId: row.optString('service_type_id'),
        totalServices: row.integer('total_services'),
        completed: row.integer('completed'),
        deliveredMinutes: row.integer('delivered_minutes'),
      ),
    ),
    facilities: json.objectList(
      'facilities',
      (row) => FacilityReportRow(
        facilityId: row.string('facility_id'),
        facilityName: row.string('facility_name'),
        totalServices: row.integer('total_services'),
        completed: row.integer('completed'),
        deliveredMinutes: row.integer('delivered_minutes'),
      ),
    ),
  );
}

JsonMap operationalReportToJson(OperationalReport report) => {
  'period': {
    'from': formatTimestamp(report.period.start),
    'to': formatTimestamp(report.period.end),
  },
  'facility_id': report.facilityId,
  'generated_at': formatTimestamp(report.generatedAt),
  'total_services': report.totalServices,
  'by_status': _statusCountsToJson(report.byStatus),
  'started_services': report.startedServices,
  'on_time_starts': report.onTimeStarts,
  'on_time_tolerance_minutes': report.onTimeToleranceMinutes,
  'average_start_delay_minutes': report.averageStartDelayMinutes,
  'scheduled_minutes': report.scheduledMinutes,
  'delivered_minutes': report.deliveredMinutes,
  'change_request_count': report.changeRequestCount,
  'change_requests_by_reason': {
    for (final reason in ChangeRequestReason.values)
      reason.code: report.changeRequestsByReason[reason] ?? 0,
  },
  'daily': [
    for (final day in report.daily)
      {
        'date': formatDate(day.day),
        'by_status': _statusCountsToJson(day.byStatus),
      },
  ],
  'operators': [
    for (final row in report.operators)
      {
        'operator_id': row.operatorId,
        'operator_name': row.operatorName,
        'operator_code': row.operatorCode,
        'total_services': row.totalServices,
        'completed': row.completed,
        'not_executed': row.notExecuted,
        'cancelled': row.cancelled,
        'scheduled_minutes': row.scheduledMinutes,
        'delivered_minutes': row.deliveredMinutes,
        'average_start_delay_minutes': row.averageStartDelayMinutes,
      },
  ],
  'service_types': [
    for (final row in report.serviceTypes)
      {
        'label': row.label,
        'service_type_id': row.serviceTypeId,
        'total_services': row.totalServices,
        'completed': row.completed,
        'delivered_minutes': row.deliveredMinutes,
      },
  ],
  'facilities': [
    for (final row in report.facilities)
      {
        'facility_id': row.facilityId,
        'facility_name': row.facilityName,
        'total_services': row.totalServices,
        'completed': row.completed,
        'delivered_minutes': row.deliveredMinutes,
      },
  ],
};

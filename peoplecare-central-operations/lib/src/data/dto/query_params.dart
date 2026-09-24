import '../../domain/domain.dart';
import 'json_reader.dart';

/// Parametri di query previsti da API_CONTRACT.md per le liste filtrate.
///
/// Le liste di valori sono separate da virgola; i parametri assenti non
/// filtrano.

Map<String, String> pageParams(PageRequest page) => {
  'page': '${page.page}',
  'page_size': '${page.pageSize}',
};

Map<String, String> rangeParams(DateRange range) => {
  'from': formatTimestamp(range.start),
  'to': formatTimestamp(range.end),
};

/// `GET /services`
Map<String, String> serviceQueryParams(ServiceQuery query, PageRequest page) {
  final params = <String, String>{
    if (query.range != null) ...rangeParams(query.range!),
    if (query.facilityIds.isNotEmpty)
      'facility_id': (query.facilityIds.toList()..sort()).join(','),
    if (query.patientId != null) 'patient_id': query.patientId!,
    if ((query.patientText ?? '').isNotEmpty) 'patient': query.patientText!,
    if (query.serviceTypeId != null) 'service_type_id': query.serviceTypeId!,
    if (query.customTypeOnly) 'custom_type': 'true',
    if (query.statuses.isNotEmpty)
      'status': query.statuses.map((s) => s.code).join(','),
    if (query.priorities.isNotEmpty)
      'priority': query.priorities.map((p) => p.code).join(','),
    if ((query.search ?? '').isNotEmpty) 'q': query.search!,
    'sort': switch (query.sort) {
      ServiceSort.scheduledStart => 'scheduled_start',
      ServiceSort.code => 'code',
      ServiceSort.patient => 'patient',
      ServiceSort.status => 'status',
      ServiceSort.priority => 'priority',
      ServiceSort.facility => 'facility',
    },
    'order': query.descending ? 'desc' : 'asc',
    ...pageParams(page),
  };
  switch (query.operator) {
    case AssignedTo(:final operatorId):
      params['operator_id'] = operatorId;
    case Unassigned():
      params['unassigned'] = 'true';
    case null:
      break;
  }
  return params;
}

/// `GET /services/calendar`
Map<String, String> calendarParams(DateRange range, Set<String> facilityIds) =>
    {
      ...rangeParams(range),
      if (facilityIds.isNotEmpty)
        'facility_id': (facilityIds.toList()..sort()).join(','),
    };

/// `GET /operators`
Map<String, String> operatorQueryParams(OperatorQuery query) => {
  if ((query.search ?? '').isNotEmpty) 'q': query.search!,
  if (query.facilityId != null) 'facility_id': query.facilityId!,
  if (query.statuses.isNotEmpty)
    'status': query.statuses.map((s) => s.code).join(','),
  if (query.qualification != null) 'qualification': query.qualification!,
};

/// `GET /change-requests`
Map<String, String> changeRequestQueryParams(ChangeRequestQuery query) => {
  if (query.statuses.isNotEmpty)
    'status': query.statuses.map((s) => s.code).join(','),
  if (query.reasons.isNotEmpty)
    'reason': query.reasons.map((r) => r.code).join(','),
  if (query.facilityId != null) 'facility_id': query.facilityId!,
  if (query.operatorId != null) 'operator_id': query.operatorId!,
  if (query.serviceId != null) 'service_id': query.serviceId!,
  if ((query.search ?? '').isNotEmpty) 'q': query.search!,
};

/// `GET /documents`
Map<String, String> documentQueryParams(
  DocumentQuery query,
  PageRequest page,
) => {
  if (query.ownerType != null) 'owner_type': query.ownerType!.code,
  if (query.ownerId != null) 'owner_id': query.ownerId!,
  if (query.categories.isNotEmpty)
    'category': query.categories.map((c) => c.code).join(','),
  if (query.source != null) 'source': query.source!.code,
  if (query.pendingReviewOnly) 'pending_review': 'true',
  if ((query.search ?? '').isNotEmpty) 'q': query.search!,
  if (query.range != null) ...rangeParams(query.range!),
  ...pageParams(page),
};

/// `GET /notifications`
Map<String, String> notificationQueryParams(NotificationQuery query) => {
  if (query.unreadOnly) 'unread': 'true',
  if (query.types.isNotEmpty) 'type': query.types.map((t) => t.code).join(','),
  'limit': '${query.limit}',
};

/// `GET /audit-log`
Map<String, String> auditQueryParams(AuditQuery query, PageRequest page) => {
  if (query.range != null) ...rangeParams(query.range!),
  if (query.actorKinds.isNotEmpty)
    'actor_kind': query.actorKinds.map((k) => k.code).join(','),
  if (query.entityTypes.isNotEmpty)
    'entity_type': query.entityTypes.map((t) => t.code).join(','),
  if (query.entityId != null) 'entity_id': query.entityId!,
  if (query.serviceId != null) 'service_id': query.serviceId!,
  if ((query.search ?? '').isNotEmpty) 'q': query.search!,
  ...pageParams(page),
};

/// `GET /reports/operational`
Map<String, String> reportQueryParams(ReportQuery query) => {
  ...rangeParams(query.period),
  if (query.facilityId != null) 'facility_id': query.facilityId!,
};

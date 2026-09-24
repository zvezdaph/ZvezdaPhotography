/// Livello di dominio: entità, filtri, repository astratti e regole pure.
///
/// Non dipende da Flutter né da alcuna implementazione dei dati.
library;

export '../core/date_range.dart';
export '../core/errors.dart';
export '../core/paging.dart';
export 'entities/audit_entry.dart';
export 'entities/central_user.dart';
export 'entities/change_request.dart';
export 'entities/document.dart';
export 'entities/facility.dart';
export 'entities/notification.dart';
export 'entities/operational_event.dart';
export 'entities/operator.dart';
export 'entities/patient.dart';
export 'entities/report.dart';
export 'entities/service.dart';
export 'entities/service_type.dart';
export 'logic/assignment_advisor.dart';
export 'logic/report_calculator.dart';
export 'logic/schedule_conflicts.dart';
export 'logic/service_alerts.dart';
export 'logic/service_policy.dart';
export 'queries/queries.dart';
export 'repositories/repositories.dart';

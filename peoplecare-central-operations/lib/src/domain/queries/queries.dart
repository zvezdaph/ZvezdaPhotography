import '../../core/date_range.dart';
import '../entities/audit_entry.dart';
import '../entities/change_request.dart';
import '../entities/document.dart';
import '../entities/notification.dart';
import '../entities/operator.dart';
import '../entities/service.dart';

/// Filtro sull'operatore assegnato.
sealed class OperatorFilter {
  const OperatorFilter();
}

/// Servizi di un operatore specifico.
final class AssignedTo extends OperatorFilter {
  const AssignedTo(this.operatorId);

  final String operatorId;
}

/// Solo servizi senza operatore.
final class Unassigned extends OperatorFilter {
  const Unassigned();
}

/// Ordinamenti disponibili per l'elenco servizi.
enum ServiceSort { scheduledStart, code, patient, status, priority, facility }

/// Filtri della gestione servizi. Tutti i criteri sono in AND; gli insiemi
/// vuoti non filtrano.
class ServiceQuery {
  const ServiceQuery({
    this.range,
    this.facilityIds = const {},
    this.operator,
    this.patientId,
    this.patientText,
    this.serviceTypeId,
    this.customTypeOnly = false,
    this.statuses = const {},
    this.priorities = const {},
    this.search,
    this.sort = ServiceSort.scheduledStart,
    this.descending = false,
  });

  /// Servizi il cui orario programmato interseca l'intervallo.
  final DateRange? range;
  final Set<String> facilityIds;
  final OperatorFilter? operator;

  /// Paziente registrato.
  final String? patientId;

  /// Testo sul nome del paziente (registrato o manuale).
  final String? patientText;
  final String? serviceTypeId;

  /// Solo servizi personalizzati (fuori catalogo).
  final bool customTypeOnly;
  final Set<ServiceStatus> statuses;
  final Set<ServicePriority> priorities;

  /// Ricerca libera su codice, paziente, indirizzo, tipologia, note.
  final String? search;
  final ServiceSort sort;
  final bool descending;

  bool get hasFilters =>
      range != null ||
      facilityIds.isNotEmpty ||
      operator != null ||
      patientId != null ||
      (patientText?.isNotEmpty ?? false) ||
      serviceTypeId != null ||
      customTypeOnly ||
      statuses.isNotEmpty ||
      priorities.isNotEmpty ||
      (search?.isNotEmpty ?? false);
}

/// Filtri sugli operatori.
class OperatorQuery {
  const OperatorQuery({
    this.search,
    this.facilityId,
    this.statuses = const {},
    this.qualification,
  });

  final String? search;

  /// Operatori che appartengono alla struttura (principale o secondaria).
  final String? facilityId;
  final Set<OperatorStatus> statuses;
  final String? qualification;
}

/// Filtri sulle richieste di modifica.
class ChangeRequestQuery {
  const ChangeRequestQuery({
    this.statuses = const {},
    this.reasons = const {},
    this.facilityId,
    this.operatorId,
    this.serviceId,
    this.search,
  });

  final Set<ChangeRequestStatus> statuses;
  final Set<ChangeRequestReason> reasons;
  final String? facilityId;
  final String? operatorId;
  final String? serviceId;
  final String? search;
}

/// Filtri sui documenti.
class DocumentQuery {
  const DocumentQuery({
    this.ownerType,
    this.ownerId,
    this.categories = const {},
    this.source,
    this.pendingReviewOnly = false,
    this.search,
    this.range,
  });

  final DocumentOwnerType? ownerType;

  /// ID del proprietario (richiede [ownerType]).
  final String? ownerId;
  final Set<DocumentCategory> categories;
  final DocumentSource? source;
  final bool pendingReviewOnly;
  final String? search;

  /// Data di caricamento.
  final DateRange? range;
}

/// Filtri sulle notifiche.
class NotificationQuery {
  const NotificationQuery({
    this.unreadOnly = false,
    this.types = const {},
    this.limit = 200,
  });

  final bool unreadOnly;
  final Set<NotificationType> types;
  final int limit;
}

/// Filtri sul registro attività.
class AuditQuery {
  const AuditQuery({
    this.range,
    this.actorKinds = const {},
    this.entityTypes = const {},
    this.entityId,
    this.serviceId,
    this.search,
  });

  final DateRange? range;
  final Set<ActorKind> actorKinds;
  final Set<AuditEntityType> entityTypes;
  final String? entityId;
  final String? serviceId;
  final String? search;
}

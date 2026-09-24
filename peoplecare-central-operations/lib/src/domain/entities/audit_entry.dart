import 'change_request.dart';

/// Tipo di entità a cui si riferisce una voce del registro attività.
enum AuditEntityType {
  servizio('servizio'),
  operatore('operatore'),
  struttura('struttura'),
  tipologiaServizio('tipologia_servizio'),
  richiestaModifica('richiesta_modifica'),
  documento('documento'),
  sessione('sessione');

  const AuditEntityType(this.code);

  final String code;

  static AuditEntityType fromCode(String code) => values.firstWhere(
    (type) => type.code == code,
    orElse: () => AuditEntityType.sessione,
  );
}

/// Codici delle azioni registrate. Il sistema può introdurne altri: la UI
/// mostra il codice grezzo quando non lo conosce.
abstract final class AuditActions {
  static const serviceCreated = 'servizio.creato';
  static const serviceUpdated = 'servizio.modificato';
  static const serviceRescheduled = 'servizio.riprogrammato';
  static const serviceReassigned = 'servizio.riassegnato';
  static const serviceCancelled = 'servizio.annullato';
  static const serviceDeleted = 'servizio.eliminato';
  static const serviceMarkedToReschedule = 'servizio.da_riprogrammare';
  static const serviceStarted = 'servizio.iniziato';
  static const serviceCompleted = 'servizio.completato';
  static const serviceNotExecuted = 'servizio.non_eseguito';

  static const documentUploaded = 'documento.caricato';
  static const documentReceived = 'documento.ricevuto';
  static const documentReviewed = 'documento.verificato';
  static const documentDeleted = 'documento.eliminato';

  static const changeRequestReceived = 'richiesta.ricevuta';
  static const changeRequestReplied = 'richiesta.risposta';
  static const changeRequestClosed = 'richiesta.chiusa';

  static const operatorCreated = 'operatore.creato';
  static const operatorUpdated = 'operatore.modificato';
  static const operatorStatusChanged = 'operatore.stato_modificato';
  static const operatorAccountLinked = 'operatore.account_collegato';
  static const operatorAccountUnlinked = 'operatore.account_scollegato';

  static const facilityCreated = 'struttura.creata';
  static const facilityUpdated = 'struttura.modificata';

  static const serviceTypeCreated = 'tipologia.creata';
  static const serviceTypeUpdated = 'tipologia.modificata';
}

/// Modifica di un singolo campo, con valori già leggibili.
class FieldChange {
  const FieldChange({
    required this.field,
    required this.label,
    this.oldValue,
    this.newValue,
  });

  /// Nome tecnico del campo (es. `scheduled_start`).
  final String field;

  /// Etichetta leggibile (es. "Inizio programmato").
  final String label;
  final String? oldValue;
  final String? newValue;
}

/// Voce del registro attività (audit).
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.occurredAt,
    required this.actorKind,
    required this.actorName,
    this.actorId,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.entityLabel,
    required this.summary,
    this.changes = const [],
    this.serviceId,
  });

  final String id;
  final DateTime occurredAt;
  final ActorKind actorKind;
  final String actorName;
  final String? actorId;

  /// Codice azione, vedi [AuditActions].
  final String action;
  final AuditEntityType entityType;
  final String entityId;
  final String entityLabel;

  /// Descrizione sintetica leggibile.
  final String summary;
  final List<FieldChange> changes;

  /// Servizio collegato, usato per la cronologia del servizio.
  final String? serviceId;
}

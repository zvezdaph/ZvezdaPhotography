import '../../core/copy_with.dart';
import '../../core/date_range.dart';

/// Stato operativo di un servizio.
///
/// I codici sono quelli condivisi con il sistema PeopleCare e con l'app
/// mobile degli operatori.
enum ServiceStatus {
  /// Creato ma senza operatore.
  daAssegnare('da_assegnare'),

  /// Operatore assegnato, servizio non ancora iniziato.
  assegnato('assegnato'),

  /// Avviato dall'operatore dall'app mobile (`actual_start` valorizzato).
  inCorso('in_corso'),

  /// Terminato dall'operatore dall'app mobile (`actual_end` valorizzato).
  completato('completato'),

  /// Annullato dalla Centrale.
  annullato('annullato'),

  /// Non eseguito (paziente assente, rifiuto, impedimento...).
  nonEseguito('non_eseguito'),

  /// Da ripianificare: l'orario attuale non è più valido.
  daRiprogrammare('da_riprogrammare');

  const ServiceStatus(this.code);

  final String code;

  static ServiceStatus fromCode(String code) => values.firstWhere(
    (status) => status.code == code,
    orElse: () =>
        throw FormatException('Stato del servizio sconosciuto: $code'),
  );

  /// Stati conclusi: il servizio non cambia più orario né operatore.
  bool get isFinal =>
      this == completato || this == annullato || this == nonEseguito;

  /// Stati in cui il servizio impegna l'operatore nel suo intervallo.
  bool get occupiesOperator =>
      this == assegnato || this == inCorso || this == completato;

  /// Stati che richiedono un intervento della Centrale.
  bool get needsAttention => this == daAssegnare || this == daRiprogrammare;
}

/// Priorità operativa.
enum ServicePriority {
  bassa('bassa', 0),
  normale('normale', 1),
  alta('alta', 2),
  urgente('urgente', 3);

  const ServicePriority(this.code, this.rank);

  final String code;

  /// Ordine crescente di urgenza.
  final int rank;

  static ServicePriority fromCode(String code) => values.firstWhere(
    (priority) => priority.code == code,
    orElse: () => throw FormatException('Priorità sconosciuta: $code'),
  );
}

/// Tipologia del servizio: voce del catalogo oppure servizio personalizzato.
sealed class ServiceKind {
  const ServiceKind();

  /// Nome da mostrare.
  String get label;
}

/// Tipologia presa dal catalogo.
final class CatalogServiceKind extends ServiceKind {
  const CatalogServiceKind({required this.serviceTypeId, required this.name});

  final String serviceTypeId;

  /// Nome della tipologia (copia di sola lettura del catalogo).
  final String name;

  @override
  String get label => name;
}

/// Servizio personalizzato, fuori catalogo.
final class CustomServiceKind extends ServiceKind {
  const CustomServiceKind(this.name);

  final String name;

  @override
  String get label => name;
}

/// Destinatario del servizio: paziente registrato oppure dati inseriti a mano.
sealed class ServicePatient {
  const ServicePatient({required this.firstName, required this.lastName});

  final String firstName;
  final String lastName;

  String get fullName => '$firstName $lastName';

  String get sortName => '$lastName $firstName';

  /// ID del paziente registrato, `null` per i dati manuali.
  String? get patientId;
}

/// Paziente presente nell'anagrafica PeopleCare.
final class RegisteredServicePatient extends ServicePatient {
  const RegisteredServicePatient({
    required this.patientId,
    required super.firstName,
    required super.lastName,
  });

  @override
  final String patientId;
}

/// Destinatario non (ancora) registrato: nome e cognome inseriti dalla Centrale.
final class ManualServicePatient extends ServicePatient {
  const ManualServicePatient({
    required super.firstName,
    required super.lastName,
  });

  @override
  String? get patientId => null;
}

/// Servizio (attività) da svolgere presso un paziente.
class Service {
  const Service({
    required this.id,
    required this.code,
    required this.kind,
    required this.facilityId,
    this.operatorId,
    required this.patient,
    required this.scheduledStart,
    required this.scheduledEnd,
    this.actualStart,
    this.actualEnd,
    required this.status,
    this.priority = ServicePriority.normale,
    required this.address,
    this.phone,
    this.directions,
    this.notes,
    this.statusReason,
    this.documentCount = 0,
    this.openChangeRequestCount = 0,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    required this.updatedBy,
    this.version = 1,
  });

  final String id;

  /// Codice leggibile, es. `SRV-2026-004812`.
  final String code;
  final ServiceKind kind;
  final String facilityId;

  /// Operatore assegnato, `null` se da assegnare.
  final String? operatorId;
  final ServicePatient patient;

  /// Orario pianificato dalla Centrale (`scheduled_start`/`scheduled_end`).
  final DateTime scheduledStart;
  final DateTime scheduledEnd;

  /// Orari reali registrati dall'app mobile (`actual_start`/`actual_end`).
  final DateTime? actualStart;
  final DateTime? actualEnd;
  final ServiceStatus status;
  final ServicePriority priority;
  final String address;
  final String? phone;

  /// Indicazioni per raggiungere il paziente / accedere al domicilio.
  final String? directions;
  final String? notes;

  /// Motivo dell'annullamento, della mancata esecuzione o della
  /// riprogrammazione.
  final String? statusReason;

  /// Numero di documenti allegati (calcolato dal sistema).
  final int documentCount;

  /// Richieste di modifica non ancora chiuse (calcolato dal sistema).
  final int openChangeRequestCount;
  final DateTime createdAt;
  final String createdBy;
  final DateTime updatedAt;
  final String updatedBy;

  /// Versione per il controllo di concorrenza ottimistica.
  final int version;

  bool get isAssigned => operatorId != null;

  bool get isCustom => kind is CustomServiceKind;

  String? get serviceTypeId => switch (kind) {
    CatalogServiceKind(:final serviceTypeId) => serviceTypeId,
    CustomServiceKind() => null,
  };

  DateRange get scheduledRange => DateRange(scheduledStart, scheduledEnd);

  Duration get scheduledDuration => scheduledEnd.difference(scheduledStart);

  Duration? get actualDuration {
    final start = actualStart;
    final end = actualEnd;
    if (start == null || end == null) return null;
    return end.difference(start);
  }

  /// Ritardo di avvio (negativo se avviato in anticipo).
  Duration? get startDelay => actualStart?.difference(scheduledStart);

  /// Intervallo in cui il servizio impegna l'operatore, considerando gli
  /// orari reali quando disponibili. Per un servizio in corso la fine è
  /// almeno [now].
  DateRange occupiedRange(DateTime now) {
    final start = actualStart ?? scheduledStart;
    DateTime end;
    switch (status) {
      case ServiceStatus.inCorso:
        end = now.isAfter(scheduledEnd) ? now : scheduledEnd;
      case ServiceStatus.completato:
        end = actualEnd ?? scheduledEnd;
      default:
        end = scheduledEnd;
    }
    if (end.isBefore(start)) end = start;
    return DateRange(start, end);
  }

  Service copyWith({
    ServiceKind? kind,
    String? facilityId,
    Object? operatorId = unset,
    ServicePatient? patient,
    DateTime? scheduledStart,
    DateTime? scheduledEnd,
    Object? actualStart = unset,
    Object? actualEnd = unset,
    ServiceStatus? status,
    ServicePriority? priority,
    String? address,
    Object? phone = unset,
    Object? directions = unset,
    Object? notes = unset,
    Object? statusReason = unset,
    int? documentCount,
    int? openChangeRequestCount,
    DateTime? updatedAt,
    String? updatedBy,
    int? version,
  }) => Service(
    id: id,
    code: code,
    kind: kind ?? this.kind,
    facilityId: facilityId ?? this.facilityId,
    operatorId: pick<String>(operatorId, this.operatorId),
    patient: patient ?? this.patient,
    scheduledStart: scheduledStart ?? this.scheduledStart,
    scheduledEnd: scheduledEnd ?? this.scheduledEnd,
    actualStart: pick<DateTime>(actualStart, this.actualStart),
    actualEnd: pick<DateTime>(actualEnd, this.actualEnd),
    status: status ?? this.status,
    priority: priority ?? this.priority,
    address: address ?? this.address,
    phone: pick<String>(phone, this.phone),
    directions: pick<String>(directions, this.directions),
    notes: pick<String>(notes, this.notes),
    statusReason: pick<String>(statusReason, this.statusReason),
    documentCount: documentCount ?? this.documentCount,
    openChangeRequestCount:
        openChangeRequestCount ?? this.openChangeRequestCount,
    createdAt: createdAt,
    createdBy: createdBy,
    updatedAt: updatedAt ?? this.updatedAt,
    updatedBy: updatedBy ?? this.updatedBy,
    version: version ?? this.version,
  );
}

/// Dati inseriti dalla Centrale per creare o modificare un servizio.
///
/// Gli allegati si caricano dopo la creazione tramite il repository dei
/// documenti (proprietario = servizio).
class ServiceDraft {
  const ServiceDraft({
    required this.kind,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.patient,
    required this.facilityId,
    this.operatorId,
    this.priority = ServicePriority.normale,
    required this.address,
    this.phone,
    this.directions,
    this.notes,
  });

  factory ServiceDraft.fromService(Service service) => ServiceDraft(
    kind: service.kind,
    scheduledStart: service.scheduledStart,
    scheduledEnd: service.scheduledEnd,
    patient: service.patient,
    facilityId: service.facilityId,
    operatorId: service.operatorId,
    priority: service.priority,
    address: service.address,
    phone: service.phone,
    directions: service.directions,
    notes: service.notes,
  );

  final ServiceKind kind;
  final DateTime scheduledStart;
  final DateTime scheduledEnd;
  final ServicePatient patient;
  final String facilityId;
  final String? operatorId;
  final ServicePriority priority;
  final String address;
  final String? phone;
  final String? directions;
  final String? notes;

  bool get hasValidSchedule => scheduledEnd.isAfter(scheduledStart);
}

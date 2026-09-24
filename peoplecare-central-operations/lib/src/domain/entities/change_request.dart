/// Motivo della richiesta di modifica inviata dall'operatore.
enum ChangeRequestReason {
  problemaOrario('problema_orario'),
  sovrapposizione('sovrapposizione'),
  indisponibilita('indisponibilita'),
  problemaLogistico('problema_logistico'),
  imprevisto('imprevisto'),
  altro('altro');

  const ChangeRequestReason(this.code);

  final String code;

  static ChangeRequestReason fromCode(String code) => values.firstWhere(
    (reason) => reason.code == code,
    orElse: () => ChangeRequestReason.altro,
  );
}

/// Stato di lavorazione della richiesta.
enum ChangeRequestStatus {
  /// Ricevuta, nessuna risposta della Centrale.
  inAttesa('in_attesa'),

  /// La Centrale ha risposto ma non ha ancora chiuso la richiesta.
  inLavorazione('in_lavorazione'),

  /// Gestita e chiusa con un esito.
  chiusa('chiusa');

  const ChangeRequestStatus(this.code);

  final String code;

  static ChangeRequestStatus fromCode(String code) => values.firstWhere(
    (status) => status.code == code,
    orElse: () =>
        throw FormatException('Stato della richiesta sconosciuto: $code'),
  );

  bool get isOpen => this != chiusa;
}

/// Esito con cui la Centrale chiude la richiesta.
enum ChangeRequestOutcome {
  orarioModificato('orario_modificato'),
  riassegnato('riassegnato'),
  assegnazioneMantenuta('assegnazione_mantenuta');

  const ChangeRequestOutcome(this.code);

  final String code;

  static ChangeRequestOutcome fromCode(String code) => values.firstWhere(
    (outcome) => outcome.code == code,
    orElse: () =>
        throw FormatException('Esito della richiesta sconosciuto: $code'),
  );
}

/// Autore di un messaggio o di un'azione.
enum ActorKind {
  centrale('centrale'),
  operatore('operatore'),
  sistema('sistema');

  const ActorKind(this.code);

  final String code;

  static ActorKind fromCode(String code) => values.firstWhere(
    (kind) => kind.code == code,
    orElse: () => ActorKind.sistema,
  );
}

/// Messaggio nel dialogo tra operatore e Centrale su una richiesta.
class ChangeRequestMessage {
  const ChangeRequestMessage({
    required this.id,
    required this.authorKind,
    required this.authorName,
    required this.text,
    required this.sentAt,
  });

  final String id;
  final ActorKind authorKind;
  final String authorName;
  final String text;
  final DateTime sentAt;
}

/// Richiesta di modifica inviata dall'operatore sul territorio.
///
/// L'operatore non accetta né rifiuta i servizi: segnala un problema e la
/// Centrale decide (modifica orario, riassegna, mantiene l'assegnazione,
/// risponde).
class ChangeRequest {
  const ChangeRequest({
    required this.id,
    required this.code,
    required this.serviceId,
    required this.serviceCode,
    required this.operatorId,
    required this.operatorName,
    required this.reason,
    required this.message,
    this.proposedStart,
    this.proposedEnd,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.messages = const [],
    this.outcome,
    this.closedAt,
    this.closedBy,
    this.version = 1,
  });

  final String id;

  /// Codice leggibile, es. `RM-000321`.
  final String code;
  final String serviceId;
  final String serviceCode;
  final String operatorId;
  final String operatorName;
  final ChangeRequestReason reason;

  /// Testo libero scritto dall'operatore.
  final String message;

  /// Orario alternativo proposto dall'operatore (facoltativo).
  final DateTime? proposedStart;
  final DateTime? proposedEnd;
  final ChangeRequestStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Risposte successive (Centrale e operatore), in ordine cronologico.
  final List<ChangeRequestMessage> messages;
  final ChangeRequestOutcome? outcome;
  final DateTime? closedAt;
  final String? closedBy;
  final int version;

  bool get hasProposal => proposedStart != null && proposedEnd != null;

  ChangeRequest copyWith({
    ChangeRequestStatus? status,
    DateTime? updatedAt,
    List<ChangeRequestMessage>? messages,
    ChangeRequestOutcome? outcome,
    DateTime? closedAt,
    String? closedBy,
    int? version,
  }) => ChangeRequest(
    id: id,
    code: code,
    serviceId: serviceId,
    serviceCode: serviceCode,
    operatorId: operatorId,
    operatorName: operatorName,
    reason: reason,
    message: message,
    proposedStart: proposedStart,
    proposedEnd: proposedEnd,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    messages: messages ?? this.messages,
    outcome: outcome ?? this.outcome,
    closedAt: closedAt ?? this.closedAt,
    closedBy: closedBy ?? this.closedBy,
    version: version ?? this.version,
  );
}

/// Decisione della Centrale che chiude una richiesta di modifica.
///
/// Ogni decisione può includere un messaggio per l'operatore.
sealed class ChangeRequestResolution {
  const ChangeRequestResolution({this.message});

  final String? message;

  ChangeRequestOutcome get outcome;
}

/// Nuovo orario per il servizio.
final class RescheduleResolution extends ChangeRequestResolution {
  const RescheduleResolution({
    required this.start,
    required this.end,
    super.message,
  });

  final DateTime start;
  final DateTime end;

  @override
  ChangeRequestOutcome get outcome => ChangeRequestOutcome.orarioModificato;
}

/// Servizio assegnato a un altro operatore.
final class ReassignResolution extends ChangeRequestResolution {
  const ReassignResolution({required this.operatorId, super.message});

  final String operatorId;

  @override
  ChangeRequestOutcome get outcome => ChangeRequestOutcome.riassegnato;
}

/// Nessuna modifica: l'assegnazione resta invariata.
final class KeepAssignmentResolution extends ChangeRequestResolution {
  const KeepAssignmentResolution({super.message});

  @override
  ChangeRequestOutcome get outcome =>
      ChangeRequestOutcome.assegnazioneMantenuta;
}

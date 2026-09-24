import '../../core/copy_with.dart';

/// Stato amministrativo dell'operatore.
enum OperatorStatus {
  /// Può ricevere servizi.
  attivo('attivo'),

  /// Temporaneamente non assegnabile (ferie lunghe, malattia, verifica...).
  sospeso('sospeso'),

  /// Non più operativo: resta solo per lo storico.
  disabilitato('disabilitato');

  const OperatorStatus(this.code);

  final String code;

  static OperatorStatus fromCode(String code) => values.firstWhere(
    (status) => status.code == code,
    orElse: () =>
        throw FormatException('Stato dell\'operatore sconosciuto: $code'),
  );
}

/// Stato dell'account applicativo associato all'operatore.
enum AccountStatus {
  /// Invito inviato, primo accesso non ancora effettuato.
  invitato('invitato'),
  attivo('attivo'),

  /// Accesso bloccato (tentativi falliti, revoca...).
  bloccato('bloccato');

  const AccountStatus(this.code);

  final String code;

  static AccountStatus fromCode(String code) => values.firstWhere(
    (status) => status.code == code,
    orElse: () =>
        throw FormatException('Stato dell\'account sconosciuto: $code'),
  );
}

/// Account PeopleCare con cui l'operatore accede all'app mobile.
///
/// L'autenticazione è gestita dal sistema PeopleCare: qui c'è solo il
/// collegamento, mai password o token.
class OperatorAccount {
  const OperatorAccount({
    required this.accountId,
    required this.username,
    required this.status,
    this.linkedAt,
  });

  final String accountId;

  /// Identificativo di accesso (tipicamente l'email aziendale).
  final String username;
  final AccountStatus status;
  final DateTime? linkedAt;
}

/// Operatore PeopleCare sul territorio.
///
/// Entità distinta da pazienti e clienti. Oggi un operatore appartiene di norma
/// a una sola struttura, ma il modello supporta una struttura principale e
/// un numero qualsiasi di strutture secondarie.
class Operator {
  const Operator({
    required this.id,
    required this.code,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.qualification,
    required this.primaryFacilityId,
    this.secondaryFacilityIds = const [],
    this.status = OperatorStatus.attivo,
    this.statusReason,
    this.account,
    this.lastAccessAt,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.version = 1,
  });

  /// ID interno (opaco).
  final String id;

  /// Codice operatore univoco, es. `OP-000184`.
  final String code;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;

  /// Qualifica/ruolo (es. OSS, Infermiere, Fisioterapista).
  final String qualification;
  final String primaryFacilityId;

  /// Strutture aggiuntive (seconda struttura e successive), senza duplicati e
  /// senza la struttura principale.
  final List<String> secondaryFacilityIds;
  final OperatorStatus status;

  /// Motivo dell'ultima sospensione/disabilitazione.
  final String? statusReason;
  final OperatorAccount? account;

  /// Ultimo accesso all'app mobile.
  final DateTime? lastAccessAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;

  String get fullName => '$firstName $lastName';

  /// Cognome e nome, per elenchi ordinati.
  String get sortName => '$lastName $firstName';

  String get initials {
    final first = firstName.isEmpty ? '' : firstName[0];
    final last = lastName.isEmpty ? '' : lastName[0];
    return (first + last).toUpperCase();
  }

  /// Tutte le strutture, la principale per prima.
  List<String> get facilityIds => [primaryFacilityId, ...secondaryFacilityIds];

  bool belongsTo(String facilityId) => facilityIds.contains(facilityId);

  bool get isAssignable => status == OperatorStatus.attivo;

  bool get hasAccount => account != null;

  Operator copyWith({
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
    String? qualification,
    String? primaryFacilityId,
    List<String>? secondaryFacilityIds,
    OperatorStatus? status,
    Object? statusReason = unset,
    Object? account = unset,
    Object? lastAccessAt = unset,
    Object? notes = unset,
    DateTime? updatedAt,
    int? version,
  }) => Operator(
    id: id,
    code: code,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    email: email ?? this.email,
    phone: phone ?? this.phone,
    qualification: qualification ?? this.qualification,
    primaryFacilityId: primaryFacilityId ?? this.primaryFacilityId,
    secondaryFacilityIds: secondaryFacilityIds ?? this.secondaryFacilityIds,
    status: status ?? this.status,
    statusReason: pick<String>(statusReason, this.statusReason),
    account: pick<OperatorAccount>(account, this.account),
    lastAccessAt: pick<DateTime>(lastAccessAt, this.lastAccessAt),
    notes: pick<String>(notes, this.notes),
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    version: version ?? this.version,
  );
}

/// Dati anagrafici modificabili dalla Centrale. Codice, stato e account hanno
/// operazioni dedicate.
class OperatorDraft {
  const OperatorDraft({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.qualification,
    required this.primaryFacilityId,
    this.secondaryFacilityIds = const [],
    this.notes,
  });

  factory OperatorDraft.fromOperator(Operator operator) => OperatorDraft(
    firstName: operator.firstName,
    lastName: operator.lastName,
    email: operator.email,
    phone: operator.phone,
    qualification: operator.qualification,
    primaryFacilityId: operator.primaryFacilityId,
    secondaryFacilityIds: operator.secondaryFacilityIds,
    notes: operator.notes,
  );

  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String qualification;
  final String primaryFacilityId;
  final List<String> secondaryFacilityIds;
  final String? notes;
}

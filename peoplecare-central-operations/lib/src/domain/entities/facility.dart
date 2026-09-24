import '../../core/copy_with.dart';

/// Tipologia di struttura PeopleCare.
enum FacilityKind {
  rsa('rsa'),
  centroDiurno('centro_diurno'),
  servizioDomiciliare('servizio_domiciliare'),
  comunitaAlloggio('comunita_alloggio'),
  ambulatorio('ambulatorio'),
  altro('altro');

  const FacilityKind(this.code);

  /// Codice condiviso con il sistema PeopleCare.
  final String code;

  static FacilityKind fromCode(String code) => values.firstWhere(
    (kind) => kind.code == code,
    orElse: () => FacilityKind.altro,
  );
}

/// Struttura (sede operativa) a cui appartengono operatori, pazienti e servizi.
class Facility {
  const Facility({
    required this.id,
    required this.code,
    required this.name,
    required this.kind,
    required this.address,
    required this.city,
    this.phone,
    this.email,
    this.isActive = true,
    this.notes,
    this.version = 1,
  });

  final String id;

  /// Codice leggibile, es. `STR-01`.
  final String code;
  final String name;
  final FacilityKind kind;
  final String address;
  final String city;
  final String? phone;
  final String? email;
  final bool isActive;
  final String? notes;

  /// Versione per il controllo di concorrenza ottimistica.
  final int version;

  String get fullAddress => city.isEmpty ? address : '$address, $city';

  Facility copyWith({
    String? name,
    FacilityKind? kind,
    String? address,
    String? city,
    Object? phone = unset,
    Object? email = unset,
    bool? isActive,
    Object? notes = unset,
    int? version,
  }) => Facility(
    id: id,
    code: code,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    address: address ?? this.address,
    city: city ?? this.city,
    phone: pick<String>(phone, this.phone),
    email: pick<String>(email, this.email),
    isActive: isActive ?? this.isActive,
    notes: pick<String>(notes, this.notes),
    version: version ?? this.version,
  );
}

/// Dati modificabili di una struttura (creazione/modifica).
class FacilityDraft {
  const FacilityDraft({
    required this.name,
    required this.kind,
    required this.address,
    required this.city,
    this.phone,
    this.email,
    this.isActive = true,
    this.notes,
  });

  factory FacilityDraft.fromFacility(Facility facility) => FacilityDraft(
    name: facility.name,
    kind: facility.kind,
    address: facility.address,
    city: facility.city,
    phone: facility.phone,
    email: facility.email,
    isActive: facility.isActive,
    notes: facility.notes,
  );

  final String name;
  final FacilityKind kind;
  final String address;
  final String city;
  final String? phone;
  final String? email;
  final bool isActive;
  final String? notes;
}

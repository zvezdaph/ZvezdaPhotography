/// Paziente/assistito registrato in PeopleCare.
///
/// L'anagrafica pazienti è gestita altrove: questa applicazione la consulta
/// soltanto (ricerca e selezione durante la creazione dei servizi).
class Patient {
  const Patient({
    required this.id,
    required this.code,
    required this.firstName,
    required this.lastName,
    this.birthDate,
    this.address,
    this.city,
    this.phone,
    this.facilityId,
    this.notes,
  });

  final String id;

  /// Codice leggibile, es. `PZ-004512`.
  final String code;
  final String firstName;
  final String lastName;
  final DateTime? birthDate;

  /// Indirizzo di domicilio.
  final String? address;
  final String? city;
  final String? phone;

  /// Struttura di riferimento.
  final String? facilityId;

  /// Indicazioni ricorrenti (citofono, accesso, animali...).
  final String? notes;

  String get fullName => '$firstName $lastName';

  String get sortName => '$lastName $firstName';

  String? get fullAddress {
    if (address == null) return null;
    return city == null ? address : '$address, $city';
  }
}

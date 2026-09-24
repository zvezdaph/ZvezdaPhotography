/// Voce del catalogo delle tipologie di servizio.
class ServiceType {
  const ServiceType({
    required this.id,
    required this.code,
    required this.name,
    required this.category,
    required this.defaultDurationMinutes,
    this.requiredQualifications = const [],
    this.description,
    this.isActive = true,
    this.version = 1,
  });

  final String id;

  /// Codice leggibile, es. `TS-04`.
  final String code;
  final String name;

  /// Area (es. "Assistenza di base", "Sanitaria", "Riabilitativa").
  final String category;
  final int defaultDurationMinutes;

  /// Qualifiche adatte a svolgere il servizio; vuota = qualsiasi qualifica.
  final List<String> requiredQualifications;
  final String? description;
  final bool isActive;
  final int version;

  bool acceptsQualification(String qualification) =>
      requiredQualifications.isEmpty ||
      requiredQualifications.contains(qualification);
}

/// Dati modificabili di una tipologia di servizio.
class ServiceTypeDraft {
  const ServiceTypeDraft({
    required this.name,
    required this.category,
    required this.defaultDurationMinutes,
    this.requiredQualifications = const [],
    this.description,
    this.isActive = true,
  });

  factory ServiceTypeDraft.fromServiceType(ServiceType type) =>
      ServiceTypeDraft(
        name: type.name,
        category: type.category,
        defaultDurationMinutes: type.defaultDurationMinutes,
        requiredQualifications: type.requiredQualifications,
        description: type.description,
        isActive: type.isActive,
      );

  final String name;
  final String category;
  final int defaultDurationMinutes;
  final List<String> requiredQualifications;
  final String? description;
  final bool isActive;
}

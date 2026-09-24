/// Utente della Centrale Operativa che usa l'applicazione.
class CentralUser {
  const CentralUser({
    required this.id,
    required this.displayName,
    required this.role,
    this.facilityIds = const [],
  });

  final String id;
  final String displayName;

  /// Ruolo descrittivo (es. "Operatrice di centrale", "Coordinatore").
  final String role;

  /// Strutture di competenza; vuota = tutte.
  final List<String> facilityIds;

  String get initials {
    final parts = displayName
        .split(' ')
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String get firstName {
    final parts = displayName.split(' ');
    return parts.isEmpty ? displayName : parts.first;
  }
}

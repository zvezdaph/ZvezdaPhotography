/// Normalizza un testo per le ricerche: minuscolo, senza accenti e spazi
/// superflui.
String normalizeForSearch(String value) {
  final lower = value.toLowerCase().trim();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    buffer.write(_accentMap[rune] ?? String.fromCharCode(rune));
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ');
}

/// `true` se tutte le parole di [query] compaiono in almeno uno dei [fields].
bool matchesSearch(String query, Iterable<String?> fields) {
  final normalizedQuery = normalizeForSearch(query);
  if (normalizedQuery.isEmpty) return true;
  final haystack = normalizeForSearch(fields.whereType<String>().join(' '));
  return normalizedQuery
      .split(' ')
      .where((word) => word.isNotEmpty)
      .every(haystack.contains);
}

/// `null` se [value] è vuoto o composto solo da spazi, altrimenti il testo
/// senza spazi iniziali/finali.
String? emptyToNull(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

const Map<int, String> _accentMap = {
  0xE0: 'a', // à
  0xE1: 'a', // á
  0xE2: 'a', // â
  0xE4: 'a', // ä
  0xE8: 'e', // è
  0xE9: 'e', // é
  0xEA: 'e', // ê
  0xEB: 'e', // ë
  0xEC: 'i', // ì
  0xED: 'i', // í
  0xEE: 'i', // î
  0xEF: 'i', // ï
  0xF2: 'o', // ò
  0xF3: 'o', // ó
  0xF4: 'o', // ô
  0xF6: 'o', // ö
  0xF9: 'u', // ù
  0xFA: 'u', // ú
  0xFB: 'u', // û
  0xFC: 'u', // ü
};

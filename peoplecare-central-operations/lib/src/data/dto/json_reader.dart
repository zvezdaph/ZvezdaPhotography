/// Lettura tipizzata di JSON decodificato, con errori espliciti.
///
/// Pensato per l'implementazione HTTP dei repository: ogni campo mancante o
/// del tipo sbagliato produce una [FormatException] con il percorso del campo.
typedef JsonMap = Map<String, Object?>;

extension JsonMapReader on JsonMap {
  Object? _value(String key) => this[key];

  String string(String key) {
    final value = _value(key);
    if (value is String) return value;
    throw FormatException('Campo "$key": atteso testo, trovato $value');
  }

  String? optString(String key) {
    final value = _value(key);
    if (value == null) return null;
    if (value is String) return value;
    throw FormatException('Campo "$key": atteso testo, trovato $value');
  }

  int integer(String key) {
    final value = _value(key);
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    throw FormatException('Campo "$key": atteso intero, trovato $value');
  }

  int? optInteger(String key) => _value(key) == null ? null : integer(key);

  double number(String key) {
    final value = _value(key);
    if (value is num) return value.toDouble();
    throw FormatException('Campo "$key": atteso numero, trovato $value');
  }

  double? optNumber(String key) => _value(key) == null ? null : number(key);

  bool boolean(String key) {
    final value = _value(key);
    if (value is bool) return value;
    throw FormatException('Campo "$key": atteso booleano, trovato $value');
  }

  bool optBoolean(String key, {bool fallback = false}) =>
      _value(key) == null ? fallback : boolean(key);

  DateTime timestamp(String key) => parseTimestamp(string(key), key);

  DateTime? optTimestamp(String key) {
    final value = optString(key);
    return value == null ? null : parseTimestamp(value, key);
  }

  DateTime? optDate(String key) {
    final value = optString(key);
    if (value == null) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('Campo "$key": data non valida "$value"');
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  JsonMap object(String key) {
    final value = _value(key);
    if (value is Map<String, Object?>) return value;
    if (value is Map) return value.cast<String, Object?>();
    throw FormatException('Campo "$key": atteso oggetto, trovato $value');
  }

  JsonMap? optObject(String key) => _value(key) == null ? null : object(key);

  List<Object?> _list(String key) {
    final value = _value(key);
    if (value == null) return const [];
    if (value is List) return value.cast<Object?>();
    throw FormatException('Campo "$key": attesa lista, trovato $value');
  }

  List<String> stringList(String key) => [
    for (final item in _list(key))
      if (item is String)
        item
      else
        throw FormatException('Campo "$key": attesi testi, trovato $item'),
  ];

  List<T> objectList<T>(String key, T Function(JsonMap json) decode) => [
    for (final item in _list(key))
      if (item is Map)
        decode(item.cast<String, Object?>())
      else
        throw FormatException('Campo "$key": attesi oggetti, trovato $item'),
  ];
}

/// Interpreta un timestamp RFC 3339 e lo converte in ora locale.
DateTime parseTimestamp(String value, [String key = 'timestamp']) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('Campo "$key": timestamp non valido "$value"');
  }
  return parsed.toLocal();
}

/// Timestamp RFC 3339 in UTC (millisecondi solo se presenti).
String formatTimestamp(DateTime value) {
  final utc = value.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final base =
      '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-${two(utc.day)}'
      'T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}';
  final millis = utc.millisecond;
  return millis == 0
      ? '${base}Z'
      : '$base.${millis.toString().padLeft(3, '0')}Z';
}

/// Data di calendario `YYYY-MM-DD`.
String formatDate(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-${two(value.month)}-${two(value.day)}';
}

/// Rimuove le chiavi con valore `null` (payload più compatti).
JsonMap withoutNulls(JsonMap json) => {
  for (final entry in json.entries)
    if (entry.value != null) entry.key: entry.value,
};

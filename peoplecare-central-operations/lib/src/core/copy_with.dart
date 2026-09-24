/// Supporto ai metodi `copyWith` per i campi nullabili.
///
/// Nei `copyWith` i parametri dei campi nullabili hanno come default [unset]:
/// così `copyWith(operatorId: null)` azzera il campo, mentre omettere il
/// parametro lo lascia invariato.
const Object unset = _Unset();

final class _Unset {
  const _Unset();
}

/// Restituisce [current] se [value] è [unset], altrimenti [value].
T? pick<T>(Object? value, T? current) =>
    identical(value, unset) ? current : value as T?;

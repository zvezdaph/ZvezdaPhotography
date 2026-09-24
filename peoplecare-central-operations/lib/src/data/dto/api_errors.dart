import '../../domain/domain.dart';
import 'json_reader.dart';

/// Traduzione delle risposte di errore delle API (API_CONTRACT.md, sezione
/// "Errori") nelle eccezioni del dominio, le sole che la UI conosce.
///
/// Formato atteso del corpo:
/// `{"error": {"code": "...", "message": "...", "field_errors": {...}}}`.
/// Se il corpo manca o non è leggibile decide lo status HTTP.
RepositoryException exceptionFromApiError(int statusCode, Object? body) {
  final error = _errorObject(body);
  final code = error?.optString('code');
  final message = error?.optString('message');
  final fieldErrors = <String, String>{
    for (final MapEntry(:key, :value)
        in (error?.optObject('field_errors') ?? const <String, Object?>{})
            .entries)
      if (value is String) key: value,
  };

  switch (code) {
    case 'validation_error' || 'bad_request':
      return ValidationException(
        message ?? 'Controlla i dati inseriti.',
        fieldErrors: fieldErrors,
      );
    case 'version_conflict':
      return message == null
          ? const ConcurrencyConflictException()
          : ConcurrencyConflictException(message);
    case 'operation_not_allowed':
      return OperationNotAllowedException(
        message ?? 'Operazione non consentita nello stato attuale.',
      );
    case 'not_found':
      return NotFoundException(message ?? 'Elemento non trovato.');
    case 'unauthenticated':
      return message == null
          ? const UnauthenticatedException()
          : UnauthenticatedException(message);
    case 'forbidden':
      return message == null
          ? const PermissionDeniedException()
          : PermissionDeniedException(message);
  }

  return switch (statusCode) {
    400 || 422 => ValidationException(
      message ?? 'Controlla i dati inseriti.',
      fieldErrors: fieldErrors,
    ),
    401 => const UnauthenticatedException(),
    403 => const PermissionDeniedException(),
    404 => NotFoundException(message ?? 'Elemento non trovato.'),
    409 => const ConcurrencyConflictException(),
    502 || 503 || 504 => const ConnectivityException(),
    _ => const UnexpectedRepositoryException(),
  };
}

JsonMap? _errorObject(Object? body) {
  if (body is! Map) return null;
  final error = body['error'];
  if (error is! Map) return null;
  try {
    return error.cast<String, Object?>();
  } on Object {
    return null;
  }
}

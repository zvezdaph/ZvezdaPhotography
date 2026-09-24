/// Errori che un repository può restituire alla UI.
///
/// Ogni implementazione (mock oggi, API PeopleCare domani) deve tradurre i
/// propri errori tecnici in una di queste classi: la UI non conosce HTTP,
/// codici di stato o eccezioni di rete.
sealed class RepositoryException implements Exception {
  const RepositoryException(this.message);

  /// Messaggio già leggibile dall'operatore di centrale (in italiano).
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// La risorsa richiesta non esiste (o non è visibile all'utente).
final class NotFoundException extends RepositoryException {
  const NotFoundException(super.message);
}

/// La risorsa è stata modificata da qualcun altro dopo l'ultima lettura
/// (controllo di concorrenza ottimistica sul campo `version`).
final class ConcurrencyConflictException extends RepositoryException {
  const ConcurrencyConflictException([
    super.message =
        'Il dato è stato modificato da un altro utente. Ricarica e riprova.',
  ]);
}

/// Dati non validi. [fieldErrors] associa il nome del campo al messaggio.
final class ValidationException extends RepositoryException {
  const ValidationException(super.message, {this.fieldErrors = const {}});

  final Map<String, String> fieldErrors;
}

/// Operazione non consentita nello stato attuale (es. eliminare un servizio
/// già avviato, riprogrammare un servizio completato).
final class OperationNotAllowedException extends RepositoryException {
  const OperationNotAllowedException(super.message);
}

/// L'utente non ha i permessi per l'operazione.
final class PermissionDeniedException extends RepositoryException {
  const PermissionDeniedException([
    super.message = 'Non hai i permessi per eseguire questa operazione.',
  ]);
}

/// Sessione scaduta o non autenticata.
final class UnauthenticatedException extends RepositoryException {
  const UnauthenticatedException([
    super.message = 'Sessione scaduta: effettua di nuovo l\'accesso.',
  ]);
}

/// Il sistema PeopleCare non è raggiungibile.
final class ConnectivityException extends RepositoryException {
  const ConnectivityException([
    super.message = 'Impossibile contattare il sistema PeopleCare. Verifica la connessione.',
  ]);
}

/// Errore imprevisto lato sistema.
final class UnexpectedRepositoryException extends RepositoryException {
  const UnexpectedRepositoryException([
    super.message = 'Si è verificato un errore imprevisto.',
  ]);
}

/// Messaggio da mostrare all'utente per un errore qualsiasi.
String describeError(Object error) {
  if (error is RepositoryException) return error.message;
  return 'Si è verificato un errore imprevisto.';
}

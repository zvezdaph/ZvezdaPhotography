import '../entities/service.dart';

/// Regole su cosa la Centrale può fare su un servizio.
///
/// Il sistema PeopleCare resta l'autorità finale: queste regole servono ad
/// abilitare/disabilitare i comandi e a spiegare il perché, e il mock le usa
/// per comportarsi come il sistema reale.
abstract final class ServicePolicy {
  /// Durata massima di un singolo servizio.
  static const maxDuration = Duration(hours: 12);

  static const _plannable = {
    ServiceStatus.daAssegnare,
    ServiceStatus.assegnato,
    ServiceStatus.daRiprogrammare,
  };

  /// Modifica completa (orario, operatore, paziente, tipologia...).
  static bool canEdit(Service service) => _plannable.contains(service.status);

  static bool canReschedule(Service service) =>
      _plannable.contains(service.status);

  static bool canReassign(Service service) =>
      _plannable.contains(service.status);

  static bool canCancel(Service service) => _plannable.contains(service.status);

  static bool canMarkToReschedule(Service service) =>
      service.status == ServiceStatus.daAssegnare ||
      service.status == ServiceStatus.assegnato;

  /// I documenti si possono allegare in qualsiasi stato.
  static bool canAddDocuments(Service service) => true;

  /// Motivo per cui il servizio non si può eliminare, `null` se si può.
  static String? deleteBlockedReason(Service service) {
    if (service.actualStart != null ||
        service.status == ServiceStatus.inCorso ||
        service.status == ServiceStatus.completato ||
        service.status == ServiceStatus.nonEseguito) {
      return 'Il servizio è già stato avviato o concluso: resta nello storico.';
    }
    if (service.status == ServiceStatus.assegnato ||
        service.status == ServiceStatus.daRiprogrammare) {
      return 'Il servizio è assegnato a un operatore: annullalo oppure '
          'rimuovi l\'assegnazione prima di eliminarlo.';
    }
    if (service.documentCount > 0) {
      return 'Il servizio ha documenti allegati.';
    }
    if (service.openChangeRequestCount > 0) {
      return 'Il servizio ha richieste di modifica aperte.';
    }
    return null;
  }

  static bool canDelete(Service service) =>
      deleteBlockedReason(service) == null;

  /// Controllo dell'orario programmato; `null` se valido.
  static String? validateSchedule(DateTime start, DateTime end) {
    if (!end.isAfter(start)) {
      return 'L\'ora di fine deve essere successiva all\'ora di inizio.';
    }
    if (end.difference(start) > maxDuration) {
      return 'Un servizio non può durare più di ${maxDuration.inHours} ore.';
    }
    return null;
  }

  /// Stato dopo una riprogrammazione.
  static ServiceStatus statusAfterReschedule({required String? operatorId}) =>
      operatorId == null ? ServiceStatus.daAssegnare : ServiceStatus.assegnato;

  /// Stato dopo una riassegnazione: un servizio da riprogrammare resta tale
  /// finché non riceve un nuovo orario.
  static ServiceStatus statusAfterReassign({
    required ServiceStatus current,
    required String? operatorId,
  }) {
    if (current == ServiceStatus.daRiprogrammare) return current;
    return operatorId == null
        ? ServiceStatus.daAssegnare
        : ServiceStatus.assegnato;
  }

  /// Stato dopo una modifica completa.
  static ServiceStatus statusAfterUpdate({
    required ServiceStatus current,
    required String? operatorId,
    required bool scheduleChanged,
  }) {
    if (current == ServiceStatus.daRiprogrammare && !scheduleChanged) {
      return current;
    }
    return operatorId == null
        ? ServiceStatus.daAssegnare
        : ServiceStatus.assegnato;
  }
}

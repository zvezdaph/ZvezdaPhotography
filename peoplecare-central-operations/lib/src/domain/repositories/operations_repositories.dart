import '../../core/paging.dart';
import '../entities/audit_entry.dart';
import '../entities/central_user.dart';
import '../entities/change_request.dart';
import '../entities/document.dart';
import '../entities/notification.dart';
import '../entities/operational_event.dart';
import '../entities/report.dart';
import '../queries/queries.dart';

/// Richieste di modifica inviate dagli operatori.
abstract interface class ChangeRequestRepository {
  Future<List<ChangeRequest>> listChangeRequests([
    ChangeRequestQuery query = const ChangeRequestQuery(),
  ]);

  Future<ChangeRequest> getChangeRequest(String id);

  /// Risponde all'operatore senza chiudere la richiesta.
  Future<ChangeRequest> reply(
    String id, {
    required String message,
    required int expectedVersion,
  });

  /// Chiude la richiesta applicando la decisione al servizio collegato.
  Future<ChangeRequest> resolve(
    String id,
    ChangeRequestResolution resolution, {
    required int expectedVersion,
  });
}

/// Documenti associati a servizi, operatori, pazienti o alla Centrale.
abstract interface class DocumentRepository {
  Future<PagedResult<DocumentInfo>> searchDocuments(
    DocumentQuery query, {
    PageRequest page = const PageRequest(),
  });

  Future<DocumentInfo> uploadDocument(DocumentUpload upload);

  Future<DocumentContent> downloadDocument(String id);

  /// Segna come verificato un documento ricevuto dal territorio.
  Future<DocumentInfo> markReviewed(String id);

  Future<void> deleteDocument(String id);
}

/// Notifiche per gli utenti della Centrale.
abstract interface class NotificationRepository {
  Future<List<AppNotification>> listNotifications([
    NotificationQuery query = const NotificationQuery(),
  ]);

  Future<int> countUnread();

  Future<void> markRead(String id);

  Future<void> markAllRead();

  /// Notifiche nuove, in tempo reale.
  Stream<AppNotification> watchNew();
}

/// Registro attività (audit).
abstract interface class AuditRepository {
  Future<PagedResult<AuditEntry>> searchAudit(
    AuditQuery query, {
    PageRequest page = const PageRequest(),
  });
}

/// Reportistica operativa.
abstract interface class ReportRepository {
  Future<OperationalReport> getOperationalReport(ReportQuery query);
}

/// Sessione dell'utente della Centrale.
abstract interface class SessionRepository {
  Future<CentralUser> getCurrentUser();
}

/// Flusso di eventi in tempo reale ("questi dati sono cambiati").
abstract interface class OperationalEventsRepository {
  Stream<OperationalEvent> watchEvents();
}

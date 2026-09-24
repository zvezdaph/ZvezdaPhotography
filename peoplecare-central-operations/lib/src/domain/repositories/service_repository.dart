import '../../core/date_range.dart';
import '../../core/paging.dart';
import '../entities/audit_entry.dart';
import '../entities/service.dart';
import '../queries/queries.dart';

/// Servizi (attività) pianificati dalla Centrale.
///
/// Le regole di stato sono applicate dal sistema: il client le anticipa
/// (vedi `ServicePolicy`) ma deve comunque gestire
/// `OperationNotAllowedException` e `ConcurrencyConflictException`.
abstract interface class ServiceRepository {
  /// Tutti i servizi il cui orario programmato interseca [range] (calendario,
  /// dashboard). Intervallo massimo previsto: 31 giorni.
  Future<List<Service>> listServicesInRange(
    DateRange range, {
    Set<String> facilityIds = const {},
  });

  /// Ricerca paginata con filtri (gestione servizi).
  Future<PagedResult<Service>> searchServices(
    ServiceQuery query, {
    PageRequest page = const PageRequest(),
  });

  Future<Service> getService(String id);

  /// Crea il servizio: stato `assegnato` se c'è un operatore, altrimenti
  /// `da_assegnare`.
  Future<Service> createService(ServiceDraft draft);

  /// Modifica completa dei dati del servizio.
  Future<Service> updateService(
    String id,
    ServiceDraft draft, {
    required int expectedVersion,
  });

  /// Nuovo orario programmato.
  Future<Service> rescheduleService(
    String id, {
    required DateTime start,
    required DateTime end,
    String? reason,
    required int expectedVersion,
  });

  /// Nuovo operatore; `null` rimette il servizio tra quelli da assegnare.
  Future<Service> reassignService(
    String id, {
    required String? operatorId,
    String? reason,
    required int expectedVersion,
  });

  Future<Service> cancelService(
    String id, {
    required String reason,
    required int expectedVersion,
  });

  /// Segna il servizio come `da_riprogrammare`.
  Future<Service> markToReschedule(
    String id, {
    required String reason,
    required int expectedVersion,
  });

  /// Eliminazione definitiva, consentita solo per servizi mai avviati e
  /// senza documenti o richieste aperte.
  Future<void> deleteService(String id, {required int expectedVersion});

  /// Cronologia delle modifiche del servizio, dalla più recente.
  Future<List<AuditEntry>> getServiceHistory(String id);
}

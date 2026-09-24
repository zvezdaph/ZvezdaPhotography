import 'catalog_repositories.dart';
import 'operations_repositories.dart';
import 'operator_repository.dart';
import 'service_repository.dart';

export 'catalog_repositories.dart';
export 'operations_repositories.dart';
export 'operator_repository.dart';
export 'service_repository.dart';

/// Descrizione dell'origine dati attiva, mostrata nell'interfaccia.
class DataSourceInfo {
  const DataSourceInfo({
    required this.name,
    required this.isDemo,
    this.description,
  });

  /// Nome breve (es. "Demo", "PeopleCare").
  final String name;

  /// `true` se i dati sono fittizi: l'interfaccia lo segnala in modo evidente.
  final bool isDemo;
  final String? description;
}

/// Insieme dei repository usati dall'applicazione.
///
/// È l'unico punto di contatto tra interfaccia e dati: la UI riceve questo
/// oggetto dal composition root e non conosce l'implementazione concreta.
class PeopleCareRepositories {
  const PeopleCareRepositories({
    required this.dataSource,
    required this.session,
    required this.operators,
    required this.facilities,
    required this.serviceTypes,
    required this.patients,
    required this.services,
    required this.changeRequests,
    required this.documents,
    required this.notifications,
    required this.audit,
    required this.reports,
    required this.events,
    this.onDispose,
  });

  final DataSourceInfo dataSource;
  final SessionRepository session;
  final OperatorRepository operators;
  final FacilityRepository facilities;
  final ServiceTypeRepository serviceTypes;
  final PatientRepository patients;
  final ServiceRepository services;
  final ChangeRequestRepository changeRequests;
  final DocumentRepository documents;
  final NotificationRepository notifications;
  final AuditRepository audit;
  final ReportRepository reports;
  final OperationalEventsRepository events;

  /// Rilascia timer, connessioni e stream aperti dall'implementazione.
  final Future<void> Function()? onDispose;

  Future<void> dispose() async => onDispose?.call();
}

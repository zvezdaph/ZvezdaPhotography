import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:peoplecare_central_operations/src/app/app.dart';
import 'package:peoplecare_central_operations/src/app/app_config.dart';
import 'package:peoplecare_central_operations/src/app/bootstrap.dart';
import 'package:peoplecare_central_operations/src/core/clock.dart';
import 'package:peoplecare_central_operations/src/data/mock/demo_catalog.dart';
import 'package:peoplecare_central_operations/src/data/mock/demo_seeder.dart';
import 'package:peoplecare_central_operations/src/data/mock/mock_backend.dart';
import 'package:peoplecare_central_operations/src/data/mock/mock_repositories.dart';
import 'package:peoplecare_central_operations/src/domain/domain.dart';
import 'package:peoplecare_central_operations/src/platform/file_service.dart';
import 'package:peoplecare_central_operations/src/presentation/app_scope.dart';

/// Istante di riferimento dei test: giovedì 24 settembre 2026, 10:30 (ora
/// locale). I dati demo sono generati attorno a questo istante.
final testNow = DateTime(2026, 9, 24, 10, 30);

/// Formattazione italiana, come in `main.dart`.
Future<void> initItalianFormatting() async {
  await initializeDateFormatting('it_IT');
  Intl.defaultLocale = 'it_IT';
}

/// Backend demo popolato, senza latenza né simulazione.
MockBackend createSeededBackend({Clock? clock}) {
  final backend = MockBackend(
    clock: clock ?? FixedClock(testNow),
    currentUser: CentralUser(
      id: demoCentralUser.id,
      displayName: demoCentralUser.name,
      role: demoCentralUser.role,
    ),
  );
  DemoDataSeeder(backend).seed();
  return backend;
}

/// Repository demo per i test: orologio fermo, nessuna latenza, nessun
/// evento simulato.
PeopleCareRepositories createTestRepositories({Clock? clock}) =>
    createMockRepositories(
      clock: clock ?? FixedClock(testNow),
      latency: Duration.zero,
      simulateLiveActivity: false,
    );

/// Dipendenze complete dell'interfaccia, create dal composition root reale.
Future<AppDependencies> createTestDependencies({
  Clock? clock,
  FakeFileService? files,
}) => createAppDependencies(
  const AppConfig(
    dataSource: DataSourceKind.mock,
    apiBaseUrl: null,
    demoLatency: Duration.zero,
    demoLiveSimulation: false,
  ),
  clock: clock ?? FixedClock(testNow),
  files: files ?? FakeFileService(),
);

/// Avvia l'applicazione completa su una finestra 1920x1080.
Future<void> pumpApp(WidgetTester tester, AppDependencies dependencies) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(PeopleCareCentralApp(dependencies: dependencies));
  await settle(tester);
}

/// Lascia completare caricamenti e animazioni senza attendere i timer
/// periodici (orologio della barra superiore).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Smonta l'albero dei widget e rilascia le dipendenze (timer e stream).
Future<void> disposeApp(
  WidgetTester tester,
  AppDependencies dependencies,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(dependencies.dispose);
  await tester.pump(const Duration(seconds: 2));
}

/// [FileService] finto: nessuna finestra di sistema, registra i salvataggi.
class FakeFileService implements FileService {
  final List<PickedFile> filesToPick = [];
  final Map<String, Uint8List> saved = {};

  @override
  Future<List<PickedFile>> pickFiles({bool multiple = true}) async =>
      List.of(filesToPick);

  @override
  Future<String?> saveFile({
    required String suggestedName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    saved[suggestedName] = bytes;
    return 'C:\\Temp\\$suggestedName';
  }
}

// -----------------------------------------------------------------------------
// Costruttori di entità per i test di dominio
// -----------------------------------------------------------------------------

Service buildService({
  String id = 'srv-1',
  String code = 'SRV-2026-000001',
  String? operatorId = 'op-1',
  required DateTime start,
  Duration duration = const Duration(hours: 1),
  ServiceStatus status = ServiceStatus.assegnato,
  DateTime? actualStart,
  DateTime? actualEnd,
  String facilityId = 'str-1',
  ServiceKind kind = const CatalogServiceKind(
    serviceTypeId: 'ts-1',
    name: 'Igiene personale',
  ),
  ServicePriority priority = ServicePriority.normale,
  int documentCount = 0,
  int openChangeRequestCount = 0,
  int version = 1,
}) => Service(
  id: id,
  code: code,
  kind: kind,
  facilityId: facilityId,
  operatorId: operatorId,
  patient: const RegisteredServicePatient(
    patientId: 'pz-1',
    firstName: 'Maria',
    lastName: 'Bianchi',
  ),
  scheduledStart: start,
  scheduledEnd: start.add(duration),
  actualStart: actualStart,
  actualEnd: actualEnd,
  status: status,
  priority: priority,
  address: 'Via Roma 1, Bergamo',
  documentCount: documentCount,
  openChangeRequestCount: openChangeRequestCount,
  createdAt: start.subtract(const Duration(days: 2)),
  createdBy: 'Laura Bianchi',
  updatedAt: start.subtract(const Duration(days: 2)),
  updatedBy: 'Laura Bianchi',
  version: version,
);

Operator buildOperator({
  String id = 'op-1',
  String firstName = 'Anna',
  String lastName = 'Rossi',
  String qualification = 'OSS',
  String primaryFacilityId = 'str-1',
  List<String> secondaryFacilityIds = const [],
  OperatorStatus status = OperatorStatus.attivo,
}) => Operator(
  id: id,
  code: 'OP-${id.hashCode.abs().toString().padLeft(6, '0').substring(0, 6)}',
  firstName: firstName,
  lastName: lastName,
  email: '${firstName.toLowerCase()}.${lastName.toLowerCase()}@example.org',
  phone: '+39 035 000000',
  qualification: qualification,
  primaryFacilityId: primaryFacilityId,
  secondaryFacilityIds: secondaryFacilityIds,
  status: status,
  createdAt: DateTime(2025, 1, 10),
  updatedAt: DateTime(2025, 1, 10),
);

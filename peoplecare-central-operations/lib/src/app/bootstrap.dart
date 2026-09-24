import '../core/clock.dart';
import '../data/mock/mock_repositories.dart';
import '../domain/domain.dart';
import '../platform/file_selector_service.dart';
import '../platform/file_service.dart';
import '../presentation/app_scope.dart';
import 'app_config.dart';

/// Origine dati richiesta ma non ancora disponibile in questa build.
class DataSourceNotAvailableException implements Exception {
  const DataSourceNotAvailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Composition root: l'unico punto che conosce le implementazioni concrete
/// dei repository. Per collegare le API PeopleCare reali si aggiunge qui il
/// ramo [DataSourceKind.api] (vedi HANDOFF.md).
Future<AppDependencies> createAppDependencies(
  AppConfig config, {
  Clock clock = const SystemClock(),
  FileService files = const FileSelectorService(),
}) async {
  final PeopleCareRepositories repositories = switch (config.dataSource) {
    DataSourceKind.mock => createMockRepositories(
      clock: clock,
      latency: config.demoLatency,
      simulateLiveActivity: config.demoLiveSimulation,
    ),
    DataSourceKind.api => throw const DataSourceNotAvailableException(
      'L\'origine dati "api" non è ancora implementata in questa build: '
      'occorre realizzare i repository HTTP secondo API_CONTRACT.md '
      '(istruzioni in HANDOFF.md). Avviare con '
      '--dart-define=PEOPLECARE_DATA_SOURCE=mock per la modalità demo.',
    ),
  };
  final user = await repositories.session.getCurrentUser();
  final dependencies = AppDependencies(
    repositories: repositories,
    clock: clock,
    files: files,
    currentUser: user,
  );
  await dependencies.warmUp();
  return dependencies;
}

/// Origine dei dati dell'applicazione.
enum DataSourceKind {
  /// Dati dimostrativi in memoria (unica origine disponibile oggi).
  mock,

  /// API del sistema PeopleCare (da implementare, vedi HANDOFF.md).
  api,
}

/// Configurazione letta in fase di build tramite `--dart-define`.
///
/// Non contiene e non deve contenere credenziali: l'autenticazione verso il
/// sistema PeopleCare sarà gestita dall'implementazione `api` (HANDOFF.md).
class AppConfig {
  const AppConfig({
    required this.dataSource,
    required this.apiBaseUrl,
    required this.demoLatency,
    required this.demoLiveSimulation,
  });

  /// Configurazione della build corrente.
  factory AppConfig.fromEnvironment() {
    const source = String.fromEnvironment(
      'PEOPLECARE_DATA_SOURCE',
      defaultValue: 'mock',
    );
    const baseUrl = String.fromEnvironment('PEOPLECARE_API_BASE_URL');
    const latency = int.fromEnvironment(
      'PEOPLECARE_DEMO_LATENCY_MS',
      defaultValue: 180,
    );
    const simulation = bool.fromEnvironment(
      'PEOPLECARE_DEMO_SIMULATION',
      defaultValue: true,
    );
    return AppConfig(
      dataSource: switch (source) {
        'api' => DataSourceKind.api,
        _ => DataSourceKind.mock,
      },
      apiBaseUrl: baseUrl.isEmpty ? null : Uri.tryParse(baseUrl),
      demoLatency: Duration(milliseconds: latency < 0 ? 0 : latency),
      demoLiveSimulation: simulation,
    );
  }

  final DataSourceKind dataSource;

  /// Indirizzo base delle API PeopleCare (`PEOPLECARE_API_BASE_URL`).
  final Uri? apiBaseUrl;

  /// Ritardo simulato delle chiamate nella modalità demo.
  final Duration demoLatency;

  /// Simulazione degli eventi dall'app mobile nella modalità demo.
  final bool demoLiveSimulation;

  static const appName = 'PeopleCare Central Operations';
  static const appVersion = '1.0.0';
}

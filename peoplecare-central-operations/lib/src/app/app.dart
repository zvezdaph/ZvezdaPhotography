import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/errors.dart';
import '../presentation/app_scope.dart';
import '../presentation/shell/app_shell.dart';
import '../presentation/shell/sidebar.dart';
import '../presentation/theme/app_palette.dart';
import '../presentation/theme/app_theme.dart';
import 'app_config.dart';

const _locale = Locale('it', 'IT');

/// Applicazione avviata: tema, localizzazione italiana e shell.
class PeopleCareCentralApp extends StatelessWidget {
  const PeopleCareCentralApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      dependencies: dependencies,
      child: ListenableBuilder(
        listenable: dependencies.theme,
        builder: (context, _) => MaterialApp(
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: dependencies.theme.mode,
          locale: _locale,
          supportedLocales: const [_locale],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const AppShell(),
        ),
      ),
    );
  }
}

/// Avvio: mostra una schermata di caricamento mentre prepara le dipendenze,
/// oppure l'errore di configurazione.
class PeopleCareBootstrap extends StatefulWidget {
  const PeopleCareBootstrap({super.key, required this.load});

  final Future<AppDependencies> Function() load;

  @override
  State<PeopleCareBootstrap> createState() => _PeopleCareBootstrapState();
}

class _PeopleCareBootstrapState extends State<PeopleCareBootstrap> {
  AppDependencies? _dependencies;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      final dependencies = await widget.load();
      if (mounted) setState(() => _dependencies = dependencies);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    unawaited(_dependencies?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = _dependencies;
    if (dependencies != null) {
      return PeopleCareCentralApp(dependencies: dependencies);
    }
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: _locale,
      supportedLocales: const [_locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: _SplashScreen(error: _error, onRetry: _start),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.sidebar,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(size: 64),
              const SizedBox(height: 18),
              Text(
                'PeopleCare',
                style: TextStyle(
                  color: palette.sidebarText,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Central Operations',
                style: TextStyle(
                  color: palette.sidebarAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 32),
              if (error == null) ...[
                SizedBox(
                  width: 220,
                  child: LinearProgressIndicator(
                    color: palette.sidebarAccent,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Preparazione della centrale operativa…',
                  style: TextStyle(color: palette.sidebarMuted),
                ),
              ] else ...[
                Icon(Icons.error_outline, color: palette.warning, size: 36),
                const SizedBox(height: 12),
                Text(
                  'Impossibile avviare l\'applicazione',
                  style: TextStyle(
                    color: palette.sidebarText,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error is RepositoryException
                      ? describeError(error!)
                      : error.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.sidebarMuted),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.sidebarText,
                    side: BorderSide(color: palette.sidebarMuted),
                  ),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Riprova'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

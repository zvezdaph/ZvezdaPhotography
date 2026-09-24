import 'package:flutter/material.dart';

import '../core/clock.dart';
import '../domain/domain.dart';
import '../platform/file_service.dart';
import 'app_state/navigation_controller.dart';
import 'app_state/notification_center.dart';
import 'app_state/reference_data.dart';
import 'app_state/work_queue_counters.dart';

/// Tema chiaro/scuro scelto dall'utente.
class ThemeController extends ChangeNotifier {
  ThemeController([this._mode = ThemeMode.light]);

  ThemeMode _mode;

  ThemeMode get mode => _mode;

  bool get isDark => _mode == ThemeMode.dark;

  void toggle() {
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }
}

/// Dipendenze dell'interfaccia, create dal composition root
/// (`lib/src/app/bootstrap.dart`).
///
/// L'interfaccia vede solo astrazioni: [PeopleCareRepositories] per i dati e
/// [FileService] per i file locali.
class AppDependencies {
  AppDependencies({
    required this.repositories,
    required this.clock,
    required this.files,
    required this.currentUser,
    NavigationController? navigation,
    ThemeController? theme,
  }) : navigation = navigation ?? NavigationController(),
       theme = theme ?? ThemeController(),
       reference = ReferenceData(repositories),
       notifications = NotificationCenter(
         repository: repositories.notifications,
         events: repositories.events,
       ),
       counters = WorkQueueCounters(repositories: repositories, clock: clock);

  final PeopleCareRepositories repositories;
  final Clock clock;
  final FileService files;
  final CentralUser currentUser;
  final NavigationController navigation;
  final ThemeController theme;
  final ReferenceData reference;
  final NotificationCenter notifications;
  final WorkQueueCounters counters;

  DataSourceInfo get dataSource => repositories.dataSource;

  /// Primo caricamento dei dati condivisi.
  Future<void> warmUp() async {
    await Future.wait([
      reference.load(),
      notifications.refresh(),
      counters.refresh(),
    ]);
  }

  Future<void> dispose() async {
    reference.dispose();
    notifications.dispose();
    counters.dispose();
    navigation.dispose();
    theme.dispose();
    await repositories.dispose();
  }
}

/// Rende disponibili le [AppDependencies] a tutto l'albero dei widget.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.dependencies, required super.child});

  final AppDependencies dependencies;

  static AppDependencies of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope mancante sopra a questo widget');
    return scope!.dependencies;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      !identical(dependencies, oldWidget.dependencies);
}

extension AppScopeContext on BuildContext {
  AppDependencies get deps => AppScope.of(this);
}

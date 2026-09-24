import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../app_state/navigation_controller.dart';
import '../app_state/section_activity.dart';
import '../features/audit/audit_screen.dart';
import '../features/calendar/calendar_screen.dart';
import '../features/change_requests/change_requests_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/documents/documents_screen.dart';
import '../features/facilities/facilities_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/operators/operators_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/service_detail/service_detail_panel.dart';
import '../features/service_form/service_form_dialog.dart';
import '../features/service_types/service_types_screen.dart';
import '../features/services/services_screen.dart';
import '../theme/app_palette.dart';
import 'quick_search_dialog.dart';
import 'sidebar.dart';
import 'toast_overlay.dart';
import 'top_bar.dart';

/// Struttura principale: barra laterale, barra superiore, banner demo e
/// sezioni. Le sezioni visitate restano montate (filtri e scroll
/// conservati) e si aggiornano quando tornano visibili.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _visited = <AppSection>{};
  bool _collapsed = false;
  bool _autoCollapsedApplied = false;

  Future<void> _newService() async {
    final created = await showServiceForm(context);
    if (created != null && mounted) {
      unawaited(showServiceDetail(context, created.id));
    }
  }

  Widget _screenFor(AppSection section) => switch (section) {
    AppSection.dashboard => const DashboardScreen(),
    AppSection.calendar => const CalendarScreen(),
    AppSection.services => const ServicesScreen(),
    AppSection.changeRequests => const ChangeRequestsScreen(),
    AppSection.notifications => const NotificationsScreen(),
    AppSection.operators => const OperatorsScreen(),
    AppSection.facilities => const FacilitiesScreen(),
    AppSection.serviceTypes => const ServiceTypesScreen(),
    AppSection.documents => const DocumentsScreen(),
    AppSection.reports => const ReportsScreen(),
    AppSection.audit => const AuditScreen(),
  };

  Map<ShortcutActivator, VoidCallback> _shortcuts(AppDependencies deps) => {
    const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
        unawaited(_newService()),
    const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
        unawaited(showQuickSearch(context)),
    for (var i = 0; i < 9 && i < AppSection.values.length; i++)
      SingleActivator(
        LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i),
        control: true,
      ): () =>
          deps.navigation.go(AppSection.values[i]),
  };

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final width = MediaQuery.sizeOf(context).width;
    if (!_autoCollapsedApplied) {
      // Su schermi stretti (es. 1280 px con scala 150%) si parte compressi.
      _collapsed = width < 1360;
      _autoCollapsedApplied = true;
    }
    return CallbackShortcuts(
      bindings: _shortcuts(deps),
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: ToastOverlay(
            child: Row(
              children: [
                Sidebar(
                  collapsed: _collapsed,
                  onToggleCollapsed: () =>
                      setState(() => _collapsed = !_collapsed),
                ),
                Expanded(
                  child: Column(
                    children: [
                      if (deps.dataSource.isDemo) const _DemoBanner(),
                      TopBar(
                        onQuickSearch: () =>
                            unawaited(showQuickSearch(context)),
                        onNewService: () => unawaited(_newService()),
                      ),
                      Expanded(
                        child: ListenableBuilder(
                          listenable: deps.navigation,
                          builder: (context, _) {
                            final current = deps.navigation.current;
                            _visited.add(current);
                            return IndexedStack(
                              index: AppSection.values.indexOf(current),
                              children: [
                                for (final section in AppSection.values)
                                  _visited.contains(section)
                                      ? SectionActivity(
                                          active: section == current,
                                          child: ExcludeFocus(
                                            excluding: section != current,
                                            child: TickerMode(
                                              enabled: section == current,
                                              child: _screenFor(section),
                                            ),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      height: 30,
      color: palette.demoBanner,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Icon(Icons.science_outlined, size: 16, color: palette.demoBannerText),
          const SizedBox(width: 8),
          Text(
            'MODALITÀ DEMO',
            style: TextStyle(
              color: palette.demoBannerText,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Dati fittizi generati in memoria: nessun collegamento al sistema '
              'PeopleCare. Le modifiche si perdono alla chiusura.',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.demoBannerText, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

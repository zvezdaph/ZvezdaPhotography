import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/domain.dart';
import '../../app_scope.dart';
import '../../app_state/navigation_controller.dart';
import '../../app_state/section_activity.dart';
import '../../shared/formatters.dart';
import '../../shared/labels.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/filters.dart';
import '../../shared/widgets/kpi.dart';
import '../../shared/widgets/layout.dart';
import '../../shared/widgets/service_tile.dart';
import '../../shared/widgets/states.dart';
import '../../theme/app_palette.dart';
import '../../theme/status_styles.dart';
import '../service_actions/service_actions.dart';
import '../service_detail/service_detail_panel.dart';
import 'dashboard_controller.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DashboardController _controller;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    final deps = AppScope.of(context);
    _controller = DashboardController(
      repositories: deps.repositories,
      clock: deps.clock,
      reference: deps.reference,
    );
    unawaited(_controller.load());
    // Ritardi e "prossime ore" dipendono dall'orario: aggiornamento periodico.
    _clockTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_controller.refresh()),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.setActive(SectionActivity.of(context));
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _openService(Service service) {
    unawaited(showServiceDetail(context, service.id));
  }

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, deps.reference]),
      builder: (context, _) {
        if (!_controller.hasLoaded) {
          return _controller.error != null
              ? ErrorView(error: _controller.error!, onRetry: _controller.load)
              : const LoadingView(message: 'Caricamento della giornata…');
        }
        return Column(
          children: [
            RefreshingBar(visible: _controller.isLoading),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _header(context),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _KpiRow(controller: _controller),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 1100;
                        final left = Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _AlertsCard(
                              controller: _controller,
                              onOpen: _openService,
                            ),
                            const SizedBox(height: 16),
                            _UpcomingCard(
                              controller: _controller,
                              onOpen: _openService,
                            ),
                          ],
                        );
                        final right = Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _RequestsCard(controller: _controller),
                            const SizedBox(height: 16),
                            _ToPlanCard(
                              controller: _controller,
                              onOpen: _openService,
                            ),
                            const SizedBox(height: 16),
                            _FacilitiesCard(controller: _controller),
                          ],
                        );
                        if (!wide) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [left, const SizedBox(height: 16), right],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: left),
                            const SizedBox(width: 16),
                            Expanded(flex: 2, child: right),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    final deps = context.deps;
    final now = _controller.now;
    final greeting = now.hour < 13
        ? 'Buongiorno'
        : (now.hour < 18 ? 'Buon pomeriggio' : 'Buonasera');
    return PageHeader(
      title: '$greeting, ${deps.currentUser.firstName}',
      subtitle:
          '${Fmt.capitalize(Fmt.dayLong(now))} · situazione aggiornata alle ${Fmt.time(now)}',
      actions: [
        FilterMenu<String>(
          label: 'Struttura',
          icon: Icons.apartment_outlined,
          allLabel: 'Tutte le strutture',
          value: _controller.facilityId,
          options: [
            for (final facility in deps.reference.facilities)
              FilterOption(facility.id, facility.name),
          ],
          onChanged: _controller.setFacility,
        ),
        OutlinedButton.icon(
          onPressed: () => deps.navigation.go(
            AppSection.calendar,
            intent: CalendarDateIntent(now),
          ),
          icon: const Icon(Icons.calendar_month_outlined, size: 18),
          label: const Text('Calendario di oggi'),
        ),
        IconButton(
          tooltip: 'Aggiorna',
          onPressed: _controller.load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.controller});

  final DashboardController controller;

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    final c = controller;
    final active = c.activeToday.length;
    final completed = c.countToday(ServiceStatus.completato);
    final inProgress = c.countToday(ServiceStatus.inCorso);
    final unassignedToday = c.countToday(ServiceStatus.daAssegnare);
    final critical = c.alerts
        .where((a) => a.level == AlertLevel.critico)
        .length;
    final punctuality = c.punctuality;
    final tiles = [
      KpiTile(
        icon: Icons.assignment_outlined,
        label: 'Servizi di oggi',
        value: Fmt.integer(active),
        caption:
            '${Fmt.count(completed, 'completato', 'completati')} · '
            '$inProgress in corso',
        onTap: () => deps.navigation.go(
          AppSection.services,
          intent: ServicesFilterIntent(range: DateRange.day(c.now)),
        ),
      ),
      KpiTile(
        icon: Icons.play_circle_outline,
        label: 'In corso ora',
        value: Fmt.integer(inProgress),
        caption: Fmt.count(
          c.operatorsOnDuty,
          'operatore in servizio',
          'operatori in servizio',
        ),
        color: serviceStatusStyle(context, ServiceStatus.inCorso).foreground,
        onTap: () => deps.navigation.go(
          AppSection.calendar,
          intent: CalendarDateIntent(c.now),
        ),
      ),
      KpiTile(
        icon: Icons.person_search_outlined,
        label: 'Da pianificare (7 gg)',
        value: Fmt.integer(c.toPlanTotal),
        caption: unassignedToday > 0
            ? '$unassignedToday oggi senza operatore'
            : 'Da assegnare o riprogrammare',
        color: palette.warning,
        emphasis: unassignedToday > 0,
        onTap: () => deps.navigation.go(
          AppSection.services,
          intent: ServicesFilterIntent(
            statuses: const {
              ServiceStatus.daAssegnare,
              ServiceStatus.daRiprogrammare,
            },
            range: DateRange(startOfDay(c.now), addDays(startOfDay(c.now), 8)),
          ),
        ),
      ),
      KpiTile(
        icon: Icons.edit_calendar_outlined,
        label: 'Richieste di modifica',
        value: Fmt.integer(c.pendingRequests),
        caption: '${c.openRequests.length - c.pendingRequests} in lavorazione',
        color: palette.accent,
        emphasis: c.pendingRequests > 0,
        onTap: () => deps.navigation.go(
          AppSection.changeRequests,
          intent: const ChangeRequestIntent(pendingOnly: true),
        ),
      ),
      KpiTile(
        icon: Icons.report_problem_outlined,
        label: 'Anomalie',
        value: Fmt.integer(c.alerts.length),
        caption: critical == 0
            ? 'Nessuna critica'
            : Fmt.count(critical, 'critica', 'critiche'),
        color: palette.danger,
        emphasis: critical > 0,
      ),
      KpiTile(
        icon: Icons.timer_outlined,
        label: 'Puntualità di oggi',
        value: Fmt.percent(punctuality),
        caption: c.averageDelayMinutes == null
            ? 'Nessun servizio avviato'
            : 'Ritardo medio ${c.averageDelayMinutes!.round()} min',
        color: palette.success,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1400
            ? 6
            : (constraints.maxWidth >= 900 ? 3 : 2);
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

class _AlertsCard extends StatelessWidget {
  const _AlertsCard({required this.controller, required this.onOpen});

  final DashboardController controller;
  final ValueChanged<Service> onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final alerts = controller.alerts;
    return AppCard(
      title: 'Anomalie operative',
      subtitle: 'Ritardi, sovrapposizioni, servizi senza operatore',
      icon: Icons.report_problem_outlined,
      padding: EdgeInsets.zero,
      actions: [
        if (alerts.isNotEmpty) CountBadge(alerts.length, color: palette.danger),
      ],
      child: alerts.isEmpty
          ? const SizedBox(
              height: 140,
              child: EmptyView(
                title: 'Nessuna anomalia in corso',
                icon: Icons.verified_outlined,
                compact: true,
              ),
            )
          : Column(
              children: [
                for (final alert in alerts.take(10)) ...[
                  _AlertRow(alert: alert, onOpen: onOpen),
                  Divider(height: 1, color: palette.border),
                ],
                if (alerts.length > 10)
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      alerts.length == 11
                          ? 'e un\'altra anomalia…'
                          : 'e altre ${alerts.length - 10} anomalie…',
                      style: TextStyle(color: palette.textMuted),
                    ),
                  ),
              ],
            ),
    );
  }

  static Widget? quickAction(BuildContext context, ServiceAlert alert) {
    final service = alert.service;
    switch (alert.kind) {
      case ServiceAlertKind.daAssegnareImminente:
      case ServiceAlertKind.operatoreNonAttivo:
        return FilledButton.tonal(
          onPressed: () => unawaited(ServiceActions.reassign(context, service)),
          child: const Text('Assegna'),
        );
      case ServiceAlertKind.sovrapposizione:
      case ServiceAlertKind.daRiprogrammare:
        return FilledButton.tonal(
          onPressed: () =>
              unawaited(ServiceActions.reschedule(context, service)),
          child: const Text('Riprogramma'),
        );
      case ServiceAlertKind.avvioInRitardo:
        final operator = context.deps.reference.operator(service.operatorId);
        if (operator == null) return null;
        return Tooltip(
          message: 'Telefono ${operator.fullName}',
          child: TextButton.icon(
            onPressed: null,
            icon: const Icon(Icons.call_outlined, size: 16),
            label: Text(operator.phone),
          ),
        );
      default:
        return null;
    }
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert, required this.onOpen});

  final ServiceAlert alert;
  final ValueChanged<Service> onOpen;

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    final style = alertLevelStyle(context, alert.level);
    final service = alert.service;
    final now = deps.clock.now();
    final action = _AlertsCard.quickAction(context, alert);
    return InkWell(
      onTap: () => onOpen(service),
      hoverColor: palette.hover,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: style.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(style.icon, size: 19, color: style.foreground),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        alert.kind.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: style.foreground,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '${service.code} · ${service.kind.label} · ${service.patient.fullName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${Fmt.dayLabel(service.scheduledStart, now)} '
                    '${Fmt.timeRange(service.scheduledStart, service.scheduledEnd)} · '
                    '${deps.reference.operatorName(service.operatorId)} · '
                    '${describeAlert(alert, now)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            if (action != null) ...[const SizedBox(width: 8), action],
          ],
        ),
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.controller, required this.onOpen});

  final DashboardController controller;
  final ValueChanged<Service> onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final upcoming = controller.upcoming();
    final inProgress = controller.inProgress;
    return AppCard(
      title: 'In corso e prossime 3 ore',
      subtitle:
          '${inProgress.length} in corso · ${upcoming.length} in partenza',
      icon: Icons.schedule,
      padding: EdgeInsets.zero,
      child: inProgress.isEmpty && upcoming.isEmpty
          ? const SizedBox(
              height: 120,
              child: EmptyView(
                title: 'Nessun servizio nelle prossime ore',
                icon: Icons.event_available_outlined,
                compact: true,
              ),
            )
          : Column(
              children: [
                for (final service in [
                  ...inProgress,
                  ...upcoming,
                ].take(14)) ...[
                  ServiceTile(service: service, onTap: () => onOpen(service)),
                  Divider(height: 1, color: palette.border),
                ],
              ],
            ),
    );
  }
}

class _RequestsCard extends StatelessWidget {
  const _RequestsCard({required this.controller});

  final DashboardController controller;

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    final requests = controller.openRequests;
    final now = deps.clock.now();
    return AppCard(
      title: 'Richieste di modifica aperte',
      icon: Icons.edit_calendar_outlined,
      padding: EdgeInsets.zero,
      actions: [
        TextButton(
          onPressed: () => deps.navigation.go(AppSection.changeRequests),
          child: const Text('Tutte'),
        ),
      ],
      child: requests.isEmpty
          ? const SizedBox(
              height: 110,
              child: EmptyView(
                title: 'Nessuna richiesta aperta',
                icon: Icons.mark_chat_read_outlined,
                compact: true,
              ),
            )
          : Column(
              children: [
                for (final request in requests.take(5)) ...[
                  InkWell(
                    hoverColor: palette.hover,
                    onTap: () => deps.navigation.go(
                      AppSection.changeRequests,
                      intent: ChangeRequestIntent(changeRequestId: request.id),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          InitialsAvatar(
                            initials:
                                deps.reference
                                    .operator(request.operatorId)
                                    ?.initials ??
                                '?',
                            colorKey: request.operatorId,
                            size: 32,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${request.operatorName} · ${request.reason.label}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${request.serviceCode} · "${request.message}"',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.textSecondary,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              ChangeRequestStatusBadge(
                                request.status,
                                dense: true,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                Fmt.relative(request.createdAt, now),
                                style: TextStyle(
                                  color: palette.textMuted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 1, color: palette.border),
                ],
              ],
            ),
    );
  }
}

class _ToPlanCard extends StatelessWidget {
  const _ToPlanCard({required this.controller, required this.onOpen});

  final DashboardController controller;
  final ValueChanged<Service> onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final services = controller.toPlan;
    return AppCard(
      title: 'Da pianificare',
      subtitle: 'Senza operatore o da riprogrammare, prossimi 7 giorni',
      icon: Icons.person_search_outlined,
      padding: EdgeInsets.zero,
      actions: [
        if (controller.toPlanTotal > 0)
          CountBadge(controller.toPlanTotal, color: palette.warning),
      ],
      child: services.isEmpty
          ? const SizedBox(
              height: 110,
              child: EmptyView(
                title: 'Tutto pianificato',
                icon: Icons.task_alt,
                compact: true,
              ),
            )
          : Column(
              children: [
                for (final service in services.take(8)) ...[
                  ServiceTile(
                    service: service,
                    showDate: true,
                    onTap: () => onOpen(service),
                    trailing: service.status == ServiceStatus.daRiprogrammare
                        ? TextButton(
                            onPressed: () => unawaited(
                              ServiceActions.reschedule(context, service),
                            ),
                            child: const Text('Riprogramma'),
                          )
                        : TextButton(
                            onPressed: () => unawaited(
                              ServiceActions.reassign(context, service),
                            ),
                            child: const Text('Assegna'),
                          ),
                  ),
                  Divider(height: 1, color: palette.border),
                ],
              ],
            ),
    );
  }
}

class _FacilitiesCard extends StatelessWidget {
  const _FacilitiesCard({required this.controller});

  final DashboardController controller;

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    final byFacility = <String, List<Service>>{};
    for (final service in controller.activeToday) {
      byFacility.putIfAbsent(service.facilityId, () => []).add(service);
    }
    final facilities = deps.reference.facilities
        .where((f) => byFacility.containsKey(f.id))
        .toList();
    Color statusColor(ServiceStatus status) =>
        serviceStatusStyle(context, status).foreground;
    return AppCard(
      title: 'Andamento per struttura',
      subtitle: 'Servizi di oggi',
      icon: Icons.apartment_outlined,
      child: facilities.isEmpty
          ? Text(
              'Nessun servizio oggi.',
              style: TextStyle(color: palette.textMuted),
            )
          : Column(
              children: [
                for (final facility in facilities) ...[
                  Builder(
                    builder: (context) {
                      final services = byFacility[facility.id]!;
                      int count(ServiceStatus s) =>
                          services.where((x) => x.status == s).length;
                      final done =
                          count(ServiceStatus.completato) +
                          count(ServiceStatus.nonEseguito);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    facility.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  '$done / ${services.length}',
                                  style: TextStyle(
                                    color: palette.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            SegmentedProgressBar(
                              segments: [
                                (
                                  count(ServiceStatus.completato),
                                  statusColor(ServiceStatus.completato),
                                ),
                                (
                                  count(ServiceStatus.nonEseguito),
                                  statusColor(ServiceStatus.nonEseguito),
                                ),
                                (
                                  count(ServiceStatus.inCorso),
                                  statusColor(ServiceStatus.inCorso),
                                ),
                                (
                                  count(ServiceStatus.assegnato),
                                  statusColor(ServiceStatus.assegnato)
                                      .withValues(alpha: 0.35),
                                ),
                                (
                                  count(ServiceStatus.daAssegnare) +
                                      count(ServiceStatus.daRiprogrammare),
                                  statusColor(ServiceStatus.daAssegnare),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    for (final status in [
                      ServiceStatus.completato,
                      ServiceStatus.inCorso,
                      ServiceStatus.assegnato,
                      ServiceStatus.daAssegnare,
                      ServiceStatus.nonEseguito,
                    ])
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StatusDot(color: statusColor(status), size: 8),
                          const SizedBox(width: 4),
                          Text(
                            status.label,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

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
import '../../shared/widgets/states.dart';
import '../../theme/app_palette.dart';
import '../../theme/status_styles.dart';
import '../service_actions/service_actions.dart';
import '../service_detail/service_detail_panel.dart';
import '../service_form/service_form_dialog.dart';
import 'calendar_controller.dart';
import 'day_view.dart';
import 'week_view.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late final CalendarController _controller;
  late final NavigationController _navigation;
  Timer? _minuteTimer;

  @override
  void initState() {
    super.initState();
    final deps = AppScope.of(context);
    _controller = CalendarController(
      repositories: deps.repositories,
      clock: deps.clock,
      reference: deps.reference,
    );
    _navigation = deps.navigation;
    _applyIntent(_navigation.takeIntent(AppSection.calendar));
    unawaited(_controller.load());
    _navigation.addListener(_onNavigation);
    // La linea dell'ora corrente e i ritardi avanzano ogni minuto.
    _minuteTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_controller.refresh()),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.setActive(SectionActivity.of(context));
  }

  void _onNavigation() {
    if (_navigation.current != AppSection.calendar) return;
    final intent = _navigation.takeIntent(AppSection.calendar);
    if (intent != null) {
      _applyIntent(intent);
      unawaited(_controller.load());
    }
  }

  void _applyIntent(NavigationIntent? intent) {
    if (intent is CalendarDateIntent) {
      _controller.anchor = startOfDay(intent.date);
      _controller.view = intent.weekView ? CalendarView.week : CalendarView.day;
      if (intent.operatorId != null) {
        final operator = context.deps.reference.operator(intent.operatorId);
        _controller.operatorSearch = operator?.lastName ?? '';
      }
    }
  }

  @override
  void dispose() {
    _minuteTimer?.cancel();
    _navigation.removeListener(_onNavigation);
    _controller.dispose();
    super.dispose();
  }

  CalendarCallbacks get _callbacks => CalendarCallbacks(
    onOpen: (service) => unawaited(showServiceDetail(context, service.id)),
    onMove: (service, operatorId, start) =>
        unawaited(_move(service, operatorId, start)),
    onCreate: (operatorId, start) => unawaited(_create(operatorId, start)),
    onContextMenu: (service, position) =>
        unawaited(_contextMenu(service, position)),
  );

  Future<void> _move(
    Service service,
    String? operatorId,
    DateTime start,
  ) async {
    final updated = await ServiceActions.move(
      context,
      service,
      operatorId: operatorId,
      start: start,
    );
    if (updated != null) await _controller.refresh();
  }

  Future<void> _create(String? operatorId, DateTime start) async {
    final operator = context.deps.reference.operator(operatorId);
    if (operator != null && !operator.isAssignable) {
      showMessageForInactive(operator);
      return;
    }
    final created = await showServiceForm(
      context,
      prefill: ServiceFormPrefill(
        start: start,
        end: start.add(const Duration(hours: 1)),
        operatorId: operatorId,
        facilityId: _controller.facilityId ?? operator?.primaryFacilityId,
      ),
    );
    if (created != null) await _controller.refresh();
  }

  void showMessageForInactive(Operator operator) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${operator.fullName} è ${operator.status.label.toLowerCase()}: '
          'non può ricevere nuovi servizi.',
        ),
      ),
    );
  }

  Future<void> _contextMenu(Service service, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          enabled: false,
          child: Text(
            '${service.code} · ${service.patient.fullName}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'open', child: Text('Apri dettaglio')),
        PopupMenuItem(
          value: 'reschedule',
          enabled: ServicePolicy.canReschedule(service),
          child: const Text('Riprogramma…'),
        ),
        PopupMenuItem(
          value: 'reassign',
          enabled: ServicePolicy.canReassign(service),
          child: Text(service.operatorId == null ? 'Assegna…' : 'Riassegna…'),
        ),
        PopupMenuItem(
          value: 'mark',
          enabled: ServicePolicy.canMarkToReschedule(service),
          child: const Text('Segna da riprogrammare…'),
        ),
        PopupMenuItem(
          value: 'cancel',
          enabled: ServicePolicy.canCancel(service),
          child: const Text('Annulla servizio…'),
        ),
      ],
    );
    if (!mounted || action == null) return;
    Object? result;
    switch (action) {
      case 'open':
        await showServiceDetail(context, service.id);
        return;
      case 'reschedule':
        result = await ServiceActions.reschedule(context, service);
      case 'reassign':
        result = await ServiceActions.reassign(context, service);
      case 'mark':
        result = await ServiceActions.markToReschedule(context, service);
      case 'cancel':
        result = await ServiceActions.cancel(context, service);
    }
    if (result != null) await _controller.refresh();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _controller.anchor,
      firstDate: DateTime(_controller.anchor.year - 1),
      lastDate: DateTime(_controller.anchor.year + 1, 12, 31),
      locale: const Locale('it', 'IT'),
    );
    if (picked != null) _controller.goTo(picked);
  }

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, deps.reference]),
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Toolbar(controller: _controller, onPickDate: _pickDate),
            _SummaryStrip(controller: _controller),
            RefreshingBar(
              visible: _controller.isLoading && _controller.hasLoaded,
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(
                  color: context.palette.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.palette.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: !_controller.hasLoaded
                    ? (_controller.error != null
                          ? ErrorView(
                              error: _controller.error!,
                              onRetry: _controller.load,
                            )
                          : const LoadingView(
                              message: 'Caricamento calendario…',
                            ))
                    : _controller.view == CalendarView.day
                    ? DayView(controller: _controller, callbacks: _callbacks)
                    : WeekView(
                        controller: _controller,
                        callbacks: _callbacks,
                        onOpenDay: (day) {
                          _controller.anchor = startOfDay(day);
                          _controller.setView(CalendarView.day);
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller, required this.onPickDate});

  final CalendarController controller;
  final VoidCallback onPickDate;

  String get _title {
    final range = controller.range;
    if (controller.view == CalendarView.day) {
      return Fmt.capitalize(Fmt.dayLong(controller.anchor));
    }
    final last = addDays(range.end, -1);
    return '${Fmt.dayMedium(range.start)} – ${Fmt.dayMedium(last)} ${last.year}';
  }

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: controller.goToday,
            child: const Text('Oggi'),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: controller.view == CalendarView.day
                ? 'Giorno precedente'
                : 'Settimana precedente',
            onPressed: () => controller.step(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: controller.view == CalendarView.day
                ? 'Giorno successivo'
                : 'Settimana successiva',
            onPressed: () => controller.step(1),
            icon: const Icon(Icons.chevron_right),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: InkWell(
              onTap: onPickDate,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down, color: palette.textSecondary),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<CalendarView>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: CalendarView.day,
                      label: Text('Giorno'),
                    ),
                    ButtonSegment(
                      value: CalendarView.week,
                      label: Text('Settimana'),
                    ),
                  ],
                  selected: {controller.view},
                  onSelectionChanged: (value) =>
                      controller.setView(value.first),
                ),
                FilterMenu<String>(
                  label: 'Struttura',
                  icon: Icons.apartment_outlined,
                  allLabel: 'Tutte',
                  value: controller.facilityId,
                  options: [
                    for (final facility in deps.reference.facilities)
                      FilterOption(facility.id, facility.name),
                  ],
                  onChanged: controller.setFacility,
                ),
                SearchField(
                  hint: 'Filtra operatori',
                  width: 190,
                  initialValue: controller.operatorSearch,
                  onChanged: controller.setOperatorSearch,
                ),
                FilterChip(
                  avatar: Icon(
                    Icons.warning_amber_rounded,
                    size: 17,
                    color: palette.danger,
                  ),
                  label: const Text('Sovrapposizioni'),
                  tooltip: 'Mostra solo gli operatori con servizi sovrapposti',
                  selected: controller.conflictsOnly,
                  onSelected: controller.setConflictsOnly,
                ),
                MenuAnchor(
                  menuChildren: [
                    CheckboxMenuButton(
                      value: controller.showCancelled,
                      closeOnActivate: false,
                      onChanged: (value) =>
                          controller.setShowCancelled(value ?? false),
                      child: const Text('Mostra servizi annullati'),
                    ),
                    if (controller.view == CalendarView.day) ...[
                      const Divider(height: 8),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
                        child: Text(
                          'Fascia oraria',
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      for (final window in HourWindow.values)
                        RadioMenuButton<HourWindow>(
                          value: window,
                          groupValue: controller.hourWindow,
                          closeOnActivate: false,
                          onChanged: (value) {
                            if (value != null) controller.setHourWindow(value);
                          },
                          child: Text(window.label),
                        ),
                    ],
                  ],
                  builder: (context, menu, _) => IconButton(
                    tooltip: 'Opzioni di visualizzazione',
                    onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                    icon: const Icon(Icons.tune),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.controller});

  final CalendarController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final counts = controller.statusCounts;
    final conflicts = controller.conflictCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                for (final status in ServiceStatus.values)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: serviceStatusStyle(context, status).background,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: serviceStatusStyle(
                              context,
                              status,
                            ).foreground,
                            width: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${status.label} ${counts[status] ?? 0}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                if (conflicts > 0)
                  Pill(
                    label: Fmt.count(
                      conflicts,
                      'servizio sovrapposto',
                      'servizi sovrapposti',
                    ),
                    style: severityStyle(context, NotificationSeverity.critica),
                    dense: true,
                  ),
              ],
            ),
          ),
          Text(
            'Trascina per spostare · clic destro per altre azioni',
            style: TextStyle(fontSize: 12, color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

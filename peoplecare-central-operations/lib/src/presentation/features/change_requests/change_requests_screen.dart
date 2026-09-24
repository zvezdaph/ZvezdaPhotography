import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/text.dart';
import '../../../domain/domain.dart';
import '../../app_scope.dart';
import '../../app_state/navigation_controller.dart';
import '../../app_state/section_activity.dart';
import '../../shared/formatters.dart';
import '../../shared/labels.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/filters.dart';
import '../../shared/widgets/form_fields.dart';
import '../../shared/widgets/layout.dart';
import '../../shared/widgets/states.dart';
import '../../theme/app_palette.dart';
import '../../theme/status_styles.dart';
import '../service_actions/operator_picker.dart';
import '../service_detail/service_detail_panel.dart';
import 'change_requests_controller.dart';

class ChangeRequestsScreen extends StatefulWidget {
  const ChangeRequestsScreen({super.key});

  @override
  State<ChangeRequestsScreen> createState() => _ChangeRequestsScreenState();
}

class _ChangeRequestsScreenState extends State<ChangeRequestsScreen> {
  late final ChangeRequestsController _controller;
  late final NavigationController _navigation;

  @override
  void initState() {
    super.initState();
    final deps = AppScope.of(context);
    _controller = ChangeRequestsController(
      repositories: deps.repositories,
      clock: deps.clock,
    );
    _navigation = deps.navigation;
    _applyIntent();
    unawaited(_controller.load());
    _navigation.addListener(_onNavigation);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.setActive(SectionActivity.of(context));
  }

  @override
  void dispose() {
    _navigation.removeListener(_onNavigation);
    _controller.dispose();
    super.dispose();
  }

  bool _applyIntent() {
    final intent = _navigation.takeIntent(AppSection.changeRequests);
    if (intent is! ChangeRequestIntent) return false;
    _controller.tab = intent.pendingOnly
        ? RequestTab.inAttesa
        : (intent.changeRequestId != null
              ? RequestTab.tutte
              : RequestTab.daGestire);
    _controller.selectedId = intent.changeRequestId;
    return true;
  }

  void _onNavigation() {
    if (_navigation.current != AppSection.changeRequests) return;
    if (_applyIntent()) unawaited(_controller.load());
  }

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, deps.reference]),
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageHeader(
              title: 'Richieste di modifica',
              subtitle:
                  'Segnalazioni degli operatori dal territorio: la Centrale '
                  'decide se modificare l\'orario, riassegnare o mantenere.',
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 470,
                      child: Container(
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: palette.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _RequestList(controller: _controller),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: palette.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _RequestDetail(controller: _controller),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RequestList extends StatelessWidget {
  const _RequestList({required this.controller});

  final ChangeRequestsController controller;

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    final now = deps.clock.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: SegmentedButton<RequestTab>(
            showSelectedIcon: false,
            segments: [
              for (final tab in RequestTab.values)
                ButtonSegment(
                  value: tab,
                  label: Text('${tab.label} (${controller.counts[tab] ?? 0})'),
                ),
            ],
            selected: {controller.tab},
            onSelectionChanged: (value) => controller.setTab(value.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: SearchField(
                  hint: 'Operatore, servizio, testo…',
                  width: double.infinity,
                  initialValue: controller.search,
                  onChanged: controller.setSearch,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MultiFilterMenu<ChangeRequestReason>(
                label: 'Motivo',
                allLabel: 'Tutti',
                values: controller.reasons,
                options: [
                  for (final reason in ChangeRequestReason.values)
                    FilterOption(reason, reason.label),
                ],
                onChanged: controller.setReasons,
              ),
              FilterMenu<String>(
                label: 'Struttura',
                allLabel: 'Tutte',
                value: controller.facilityId,
                options: [
                  for (final facility in deps.reference.facilities)
                    FilterOption(facility.id, facility.name),
                ],
                onChanged: controller.setFacility,
              ),
            ],
          ),
        ),
        Divider(height: 1, color: palette.border),
        RefreshingBar(visible: controller.isLoading && controller.hasLoaded),
        Expanded(
          child: !controller.hasLoaded
              ? (controller.error != null
                    ? ErrorView(
                        error: controller.error!,
                        onRetry: controller.load,
                      )
                    : const LoadingView())
              : controller.requests.isEmpty
              ? const EmptyView(
                  title: 'Nessuna richiesta',
                  message: 'Non ci sono richieste con questi filtri.',
                  icon: Icons.mark_chat_read_outlined,
                )
              : ListView.separated(
                  itemCount: controller.requests.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: palette.border),
                  itemBuilder: (context, index) {
                    final request = controller.requests[index];
                    final selected = request.id == controller.selectedId;
                    final operator = deps.reference.operator(
                      request.operatorId,
                    );
                    return Material(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                                .withValues(alpha: 0.08)
                          : Colors.transparent,
                      child: InkWell(
                        onTap: () => unawaited(controller.select(request.id)),
                        hoverColor: palette.hover,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                width: 3,
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                              ),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InitialsAvatar(
                                initials: operator?.initials ?? '?',
                                colorKey: request.operatorId,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            request.operatorName,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight:
                                                  request.status ==
                                                      ChangeRequestStatus
                                                          .inAttesa
                                                  ? FontWeight.w700
                                                  : FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          Fmt.relative(request.createdAt, now),
                                          style: TextStyle(
                                            color: palette.textMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${request.reason.label} · ${request.serviceCode}',
                                      style: TextStyle(
                                        color: palette.textSecondary,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      request.message,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: palette.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        ChangeRequestStatusBadge(
                                          request.status,
                                          dense: true,
                                        ),
                                        if (request.outcome != null) ...[
                                          const SizedBox(width: 6),
                                          TagChip(request.outcome!.label),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

enum _Decision { orario, riassegna, mantieni, rispondi }

class _RequestDetail extends StatefulWidget {
  const _RequestDetail({required this.controller});

  final ChangeRequestsController controller;

  @override
  State<_RequestDetail> createState() => _RequestDetailState();
}

class _RequestDetailState extends State<_RequestDetail> {
  _Decision _decision = _Decision.orario;
  String? _requestId;
  DateTime _date = DateTime.now();
  int? _start;
  int? _end;
  String? _newOperatorId;
  final _message = TextEditingController();
  bool _busy = false;

  ChangeRequestsController get _c => widget.controller;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  /// Reimposta i campi quando cambia la richiesta selezionata.
  void _syncWith(ChangeRequest request, Service service) {
    if (_requestId == request.id) return;
    _requestId = request.id;
    final start = request.proposedStart ?? service.scheduledStart;
    final end = request.proposedEnd ?? start.add(service.scheduledDuration);
    _date = startOfDay(start);
    _start = minutesSinceMidnight(start);
    _end = end.difference(_date).inMinutes;
    _newOperatorId = null;
    _message.clear();
    _decision = switch (request.reason) {
      ChangeRequestReason.problemaOrario => _Decision.orario,
      ChangeRequestReason.indisponibilita ||
      ChangeRequestReason.sovrapposizione => _Decision.riassegna,
      _ => _Decision.rispondi,
    };
    if (!ServicePolicy.canReschedule(service) &&
        (_decision == _Decision.orario || _decision == _Decision.riassegna)) {
      _decision = _Decision.rispondi;
    }
  }

  DateTime? get _startAt =>
      _start == null ? null : combineDateAndMinutes(_date, _start!);

  DateTime? get _endAt => _end == null
      ? null
      : combineDateAndMinutes(
          addDays(_date, _end! ~/ (24 * 60)),
          _end! % (24 * 60),
        );

  Future<void> _submit() async {
    final message = emptyToNull(_message.text);
    ChangeRequestResolution? resolution;
    switch (_decision) {
      case _Decision.orario:
        final start = _startAt;
        final end = _endAt;
        if (start == null || end == null) return;
        final error = ServicePolicy.validateSchedule(start, end);
        if (error != null) {
          showMessage(context, error, error: true);
          return;
        }
        resolution = RescheduleResolution(
          start: start,
          end: end,
          message: message,
        );
      case _Decision.riassegna:
        final operatorId = _newOperatorId;
        if (operatorId == null) {
          showMessage(context, 'Scegli il nuovo operatore.', error: true);
          return;
        }
        resolution = ReassignResolution(
          operatorId: operatorId,
          message: message,
        );
      case _Decision.mantieni:
        resolution = KeepAssignmentResolution(message: message);
      case _Decision.rispondi:
        if (message == null) {
          showMessage(
            context,
            'Scrivi il messaggio per l\'operatore.',
            error: true,
          );
          return;
        }
    }
    setState(() => _busy = true);
    final result = await runGuarded(
      context,
      () => resolution == null ? _c.reply(message!) : _c.resolve(resolution),
      success: resolution == null
          ? 'Risposta inviata all\'operatore'
          : 'Richiesta chiusa: ${resolution.outcome.label.toLowerCase()}',
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result != null) _message.clear();
    });
  }

  Future<void> _chooseOperator(Service service) async {
    final type = context.deps.reference.serviceType(service.serviceTypeId);
    final choice = await showAssignOperatorDialog(
      context,
      slot: service.scheduledRange,
      facilityId: service.facilityId,
      requiredQualifications: type?.requiredQualifications ?? const [],
      currentOperatorId: service.operatorId,
      excludeServiceId: service.id,
      allowUnassign: false,
      askReason: false,
      confirmLabel: 'Seleziona',
      title: 'Nuovo operatore',
    );
    if (choice?.operatorId != null && mounted) {
      setState(() => _newOperatorId = choice!.operatorId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = _c.selected;
    final service = _c.service;
    if (request == null || service == null) {
      if (_c.detailError != null) {
        return ErrorView(error: _c.detailError!, onRetry: _c.load);
      }
      if (_c.loadingDetail || !_c.hasLoaded) return const LoadingView();
      return const EmptyView(
        title: 'Seleziona una richiesta',
        icon: Icons.forum_outlined,
      );
    }
    _syncWith(request, service);
    final deps = context.deps;
    final palette = context.palette;
    final now = deps.clock.now();
    final operator = deps.reference.operator(request.operatorId);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Text(request.code, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(width: 10),
            ChangeRequestStatusBadge(request.status),
            const SizedBox(width: 6),
            TagChip(request.reason.label, icon: Icons.label_outline),
            const Spacer(),
            Text(
              'Ricevuta ${Fmt.relative(request.createdAt, now)} · ${Fmt.dateTime(request.createdAt)}',
              style: TextStyle(color: palette.textMuted, fontSize: 12.5),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _MessageBubble(
          author: request.operatorName,
          subtitle: operator == null
              ? 'Operatore'
              : '${operator.qualification} · ${operator.phone}',
          text: request.message,
          at: request.createdAt,
          fromOperator: true,
          footer: request.hasProposal
              ? 'Propone: ${Fmt.slot(request.proposedStart!, request.proposedEnd!)}'
              : null,
        ),
        for (final message in request.messages)
          _MessageBubble(
            author: message.authorName,
            subtitle: message.authorKind.label,
            text: message.text,
            at: message.sentAt,
            fromOperator: message.authorKind == ActorKind.operatore,
          ),
        const SizedBox(height: 12),
        _ServiceSummary(service: service, controller: _c),
        const SizedBox(height: 18),
        if (request.status.isOpen)
          _decisionPanel(context, request, service)
        else
          InlineBanner(
            style: changeRequestStatusStyle(
              context,
              ChangeRequestStatus.chiusa,
            ),
            title: 'Richiesta chiusa · ${request.outcome?.label ?? ''}',
            message:
                'Gestita da ${request.closedBy ?? '—'} il '
                '${request.closedAt == null ? '—' : Fmt.dateTime(request.closedAt!)}.',
          ),
      ],
    );
  }

  Widget _decisionPanel(
    BuildContext context,
    ChangeRequest request,
    Service service,
  ) {
    final deps = context.deps;
    final palette = context.palette;
    final plannable = ServicePolicy.canReschedule(service);
    final start = _startAt;
    final end = _endAt;
    final slotValid =
        start != null &&
        end != null &&
        ServicePolicy.validateSchedule(start, end) == null;
    final overlaps = slotValid
        ? _c.overlapsFor(DateRange(start, end), service.operatorId)
        : const <Service>[];
    final newOperator = deps.reference.operator(_newOperatorId);
    return AppCard(
      title: 'Decisione della Centrale',
      icon: Icons.gavel_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<_Decision>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: _Decision.orario,
                label: const Text('Modifica orario'),
                icon: const Icon(Icons.update, size: 17),
                enabled: plannable,
              ),
              ButtonSegment(
                value: _Decision.riassegna,
                label: const Text('Riassegna'),
                icon: const Icon(Icons.swap_horiz, size: 17),
                enabled: plannable,
              ),
              const ButtonSegment(
                value: _Decision.mantieni,
                label: Text('Mantieni assegnazione'),
                icon: Icon(Icons.check, size: 17),
              ),
              const ButtonSegment(
                value: _Decision.rispondi,
                label: Text('Solo risposta'),
                icon: Icon(Icons.reply_outlined, size: 17),
              ),
            ],
            selected: {_decision},
            onSelectionChanged: (value) =>
                setState(() => _decision = value.first),
          ),
          if (!plannable)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Il servizio è ${service.status.label.toLowerCase()}: '
                'orario e operatore non sono più modificabili.',
                style: TextStyle(color: palette.textMuted, fontSize: 12.5),
              ),
            ),
          const SizedBox(height: 16),
          switch (_decision) {
            _Decision.orario => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DateField(
                        label: 'Nuova data',
                        value: _date,
                        onChanged: (value) =>
                            setState(() => _date = startOfDay(value)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TimeField(
                        label: 'Inizio',
                        value: _start,
                        onChanged: (value) => setState(() {
                          if (value != null && _start != null && _end != null) {
                            _end = value + (_end! - _start!);
                          }
                          _start = value;
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TimeField(
                        label: 'Fine',
                        value: _end == null ? null : _end! % (24 * 60),
                        onChanged: (value) => setState(() {
                          _end = value == null
                              ? null
                              : (_start != null && value <= _start!
                                    ? value + 24 * 60
                                    : value);
                        }),
                      ),
                    ),
                  ],
                ),
                if (request.hasProposal)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Precompilato con l\'orario proposto dall\'operatore.',
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                if (overlaps.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  InlineBanner(
                    style: severityStyle(
                      context,
                      NotificationSeverity.attenzione,
                    ),
                    title: 'Sovrapposizione per l\'operatore',
                    message: overlaps
                        .map(
                          (s) =>
                              '${s.code} · ${Fmt.timeRange(s.scheduledStart, s.scheduledEnd)} · ${s.patient.fullName}',
                        )
                        .join('\n'),
                  ),
                ],
              ],
            ),
            _Decision.riassegna => Row(
              children: [
                if (newOperator != null) ...[
                  InitialsAvatar(
                    initials: newOperator.initials,
                    colorKey: newOperator.id,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${newOperator.fullName} · ${newOperator.qualification}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ] else
                  Expanded(
                    child: Text(
                      'Nessun operatore scelto. I suggerimenti tengono conto '
                      'di disponibilità, struttura e qualifica.',
                      style: TextStyle(color: palette.textSecondary),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_chooseOperator(service)),
                  icon: const Icon(Icons.person_search_outlined, size: 18),
                  label: Text(
                    newOperator == null ? 'Scegli operatore…' : 'Cambia…',
                  ),
                ),
              ],
            ),
            _Decision.mantieni => Text(
              'Orario e operatore restano invariati. L\'operatore riceve '
              'l\'esito e l\'eventuale messaggio.',
              style: TextStyle(color: palette.textSecondary),
            ),
            _Decision.rispondi => Text(
              'Invia un messaggio senza chiudere la richiesta (stato '
              '"in lavorazione").',
              style: TextStyle(color: palette.textSecondary),
            ),
          },
          const SizedBox(height: 14),
          TextField(
            controller: _message,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: _decision == _Decision.rispondi
                  ? 'Messaggio per l\'operatore *'
                  : 'Messaggio per l\'operatore (facoltativo)',
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _busy ? null : () => unawaited(_submit()),
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _decision == _Decision.rispondi
                          ? Icons.send_outlined
                          : Icons.task_alt,
                      size: 18,
                    ),
              label: Text(switch (_decision) {
                _Decision.orario => 'Applica nuovo orario e chiudi',
                _Decision.riassegna => 'Riassegna e chiudi',
                _Decision.mantieni => 'Conferma e chiudi',
                _Decision.rispondi => 'Invia risposta',
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.author,
    required this.subtitle,
    required this.text,
    required this.at,
    required this.fromOperator,
    this.footer,
  });

  final String author;
  final String subtitle;
  final String text;
  final DateTime at;
  final bool fromOperator;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final primary = Theme.of(context).colorScheme.primary;
    final color = fromOperator ? palette.accent : primary;
    return Align(
      alignment: fromOperator ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    fromOperator ? Icons.phone_android : Icons.support_agent,
                    size: 16,
                    color: color,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '$author · $subtitle',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: color,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    Fmt.dateTime(at),
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(text, style: const TextStyle(fontSize: 14.5)),
              if (footer != null) ...[
                const SizedBox(height: 8),
                TagChip(footer!, icon: Icons.schedule, color: color),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceSummary extends StatelessWidget {
  const _ServiceSummary({required this.service, required this.controller});

  final Service service;
  final ChangeRequestsController controller;

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    final conflicts = const ScheduleConflictDetector()
        .detect(controller.dayServices, now: deps.clock.now())
        .where((c) => c.involves(service.id))
        .toList();
    return AppCard(
      title: 'Servizio ${service.code}',
      subtitle: '${service.kind.label} · ${service.patient.fullName}',
      icon: Icons.assignment_outlined,
      actions: [
        TextButton.icon(
          onPressed: () => unawaited(showServiceDetail(context, service.id)),
          icon: const Icon(Icons.open_in_new, size: 17),
          label: const Text('Apri servizio'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ServiceStatusBadge(service.status),
              PriorityBadge(service.priority),
            ],
          ),
          const SizedBox(height: 8),
          InfoRow(
            label: 'Orario attuale',
            icon: Icons.schedule,
            value: Fmt.slot(service.scheduledStart, service.scheduledEnd),
          ),
          InfoRow(
            label: 'Operatore',
            icon: Icons.badge_outlined,
            value: deps.reference.operatorName(service.operatorId),
          ),
          InfoRow(
            label: 'Struttura',
            icon: Icons.apartment_outlined,
            value: deps.reference.facilityName(service.facilityId),
          ),
          InfoRow(
            label: 'Indirizzo',
            icon: Icons.place_outlined,
            value: service.address,
          ),
          for (final conflict in conflicts)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InlineBanner(
                style: severityStyle(context, NotificationSeverity.critica),
                message:
                    'Sovrapposto a ${conflict.other(service.id).code} '
                    '(${Fmt.timeRange(conflict.other(service.id).scheduledStart, conflict.other(service.id).scheduledEnd)}).',
              ),
            ),
          if (conflicts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Nessuna sovrapposizione per l\'operatore in questa giornata.',
                style: TextStyle(color: palette.textMuted, fontSize: 12.5),
              ),
            ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/domain.dart';
import '../../app_scope.dart';
import '../../app_state/navigation_controller.dart';
import '../../app_state/screen_controller.dart';
import '../../shared/formatters.dart';
import '../../shared/labels.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/layout.dart';
import '../../shared/widgets/states.dart';
import '../../theme/app_palette.dart';
import '../../theme/status_styles.dart';
import '../documents/document_list.dart';
import '../operators/operator_detail_panel.dart';
import '../service_actions/service_actions.dart';

enum ServiceDetailTab { dettagli, documenti, richieste, cronologia }

/// Apre il dettaglio di un servizio nel pannello laterale.
Future<void> showServiceDetail(
  BuildContext context,
  String serviceId, {
  ServiceDetailTab initialTab = ServiceDetailTab.dettagli,
}) {
  return showSidePanel<void>(
    context,
    width: 780,
    builder: (_) =>
        ServiceDetailPanel(serviceId: serviceId, initialTab: initialTab),
  );
}

class ServiceDetailController extends ScreenController {
  ServiceDetailController({
    required PeopleCareRepositories repositories,
    required this.serviceId,
    required this.now,
  }) : _repositories = repositories,
       super(
         events: repositories.events,
         topics: const {
           OperationalEventTopic.servizi,
           OperationalEventTopic.documenti,
           OperationalEventTopic.richiesteModifica,
         },
       );

  final PeopleCareRepositories _repositories;
  final String serviceId;
  final DateTime Function() now;

  Service? service;
  Patient? patient;
  List<DocumentInfo> documents = const [];
  List<ChangeRequest> requests = const [];
  List<AuditEntry> history = const [];
  List<ScheduleConflict> conflicts = const [];
  bool deleted = false;

  @override
  Future<void> fetch() async {
    final loaded = await _repositories.services.getService(serviceId);
    final results = await Future.wait<Object>([
      _repositories.documents.searchDocuments(
        DocumentQuery(
          ownerType: DocumentOwnerType.servizio,
          ownerId: serviceId,
        ),
        page: const PageRequest(pageSize: 200),
      ),
      _repositories.changeRequests.listChangeRequests(
        ChangeRequestQuery(serviceId: serviceId),
      ),
      _repositories.services.getServiceHistory(serviceId),
      _repositories.services.listServicesInRange(
        DateRange.day(loaded.scheduledStart),
      ),
    ]);
    final patientId = loaded.patient.patientId;
    Patient? loadedPatient;
    if (patientId != null) {
      try {
        loadedPatient = await _repositories.patients.getPatient(patientId);
      } on NotFoundException {
        loadedPatient = null;
      }
    }
    service = loaded;
    patient = loadedPatient;
    documents = (results[0] as PagedResult<DocumentInfo>).items;
    requests = results[1] as List<ChangeRequest>;
    history = results[2] as List<AuditEntry>;
    conflicts = [
      for (final conflict in const ScheduleConflictDetector().detect(
        results[3] as List<Service>,
        now: now(),
      ))
        if (conflict.involves(serviceId)) conflict,
    ];
  }
}

class ServiceDetailPanel extends StatefulWidget {
  const ServiceDetailPanel({
    super.key,
    required this.serviceId,
    this.initialTab = ServiceDetailTab.dettagli,
  });

  final String serviceId;
  final ServiceDetailTab initialTab;

  @override
  State<ServiceDetailPanel> createState() => _ServiceDetailPanelState();
}

class _ServiceDetailPanelState extends State<ServiceDetailPanel> {
  late final ServiceDetailController _controller;

  @override
  void initState() {
    super.initState();
    final deps = AppScope.of(context);
    _controller = ServiceDetailController(
      repositories: deps.repositories,
      serviceId: widget.serviceId,
      now: deps.clock.now,
    );
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _afterAction(Future<Object?> action) async {
    final result = await action;
    if (result != null) await _controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final service = _controller.service;
        final error = _controller.error;
        if (service == null) {
          if (error != null) {
            return Column(
              children: [
                _PanelTopBar(title: 'Servizio'),
                Expanded(
                  child: error is NotFoundException
                      ? const EmptyView(
                          title: 'Servizio non più disponibile',
                          message: 'Potrebbe essere stato eliminato.',
                          icon: Icons.delete_outline,
                        )
                      : ErrorView(error: error, onRetry: _controller.load),
                ),
              ],
            );
          }
          return const LoadingView(message: 'Caricamento servizio…');
        }
        return DefaultTabController(
          length: ServiceDetailTab.values.length,
          initialIndex: widget.initialTab.index,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                service: service,
                onEdit: () =>
                    _afterAction(ServiceActions.edit(context, service)),
                onReschedule: () =>
                    _afterAction(ServiceActions.reschedule(context, service)),
                onReassign: () =>
                    _afterAction(ServiceActions.reassign(context, service)),
                onCancel: () =>
                    _afterAction(ServiceActions.cancel(context, service)),
                onMarkToReschedule: () => _afterAction(
                  ServiceActions.markToReschedule(context, service),
                ),
                onDuplicate: () =>
                    _afterAction(ServiceActions.duplicate(context, service)),
                onDelete: () async {
                  final deleted = await ServiceActions.delete(context, service);
                  if (deleted && context.mounted) Navigator.of(context).pop();
                },
              ),
              RefreshingBar(
                visible: _controller.isLoading && _controller.hasLoaded,
              ),
              _Alerts(controller: _controller),
              TabBar(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tabs: [
                  const Tab(text: 'Dettagli'),
                  Tab(text: 'Documenti (${_controller.documents.length})'),
                  Tab(
                    text:
                        'Richieste di modifica (${_controller.requests.length})',
                  ),
                  Tab(text: 'Cronologia (${_controller.history.length})'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _DetailsTab(controller: _controller),
                    _DocumentsTab(
                      controller: _controller,
                      onAdd: () => _afterAction(
                        ServiceActions.addDocuments(
                          context,
                          service,
                        ).then((docs) => docs.isEmpty ? null : docs),
                      ),
                    ),
                    _RequestsTab(controller: _controller),
                    _HistoryTab(history: _controller.history),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PanelTopBar extends StatelessWidget {
  const _PanelTopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        IconButton(
          tooltip: 'Chiudi',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.service,
    required this.onEdit,
    required this.onReschedule,
    required this.onReassign,
    required this.onCancel,
    required this.onMarkToReschedule,
    required this.onDuplicate,
    required this.onDelete,
  });

  final Service service;
  final VoidCallback onEdit;
  final VoidCallback onReschedule;
  final VoidCallback onReassign;
  final VoidCallback onCancel;
  final VoidCallback onMarkToReschedule;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final reference = context.deps.reference;
    final style = serviceStatusStyle(context, service.status);
    final deleteBlocked = ServicePolicy.deleteBlockedReason(service);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: style.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: style.border),
                ),
                child: Icon(style.icon, color: style.foreground),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SelectableText(
                          service.code,
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copia codice',
                          visualDensity: VisualDensity.compact,
                          iconSize: 15,
                          onPressed: () {
                            unawaited(
                              Clipboard.setData(
                                ClipboardData(text: service.code),
                              ),
                            );
                            showMessage(context, 'Codice copiato');
                          },
                          icon: const Icon(Icons.copy),
                        ),
                      ],
                    ),
                    Text(
                      service.kind.label,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${service.patient.fullName} · '
                      '${Fmt.slot(service.scheduledStart, service.scheduledEnd)}',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Chiudi',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ServiceStatusBadge(service.status),
              PriorityBadge(service.priority),
              TagChip(
                reference.facilityName(service.facilityId),
                icon: Icons.apartment_outlined,
              ),
              if (service.isCustom)
                const TagChip('Servizio personalizzato', icon: Icons.edit_note),
              if (service.patient is ManualServicePatient)
                const TagChip(
                  'Paziente inserito manualmente',
                  icon: Icons.person_outline,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionButton(
                label: 'Modifica',
                icon: Icons.edit_outlined,
                primary: true,
                enabled: ServicePolicy.canEdit(service),
                disabledReason:
                    'Servizio ${service.status.label.toLowerCase()}: non modificabile.',
                onPressed: onEdit,
              ),
              _ActionButton(
                label: 'Riprogramma',
                icon: Icons.update,
                enabled: ServicePolicy.canReschedule(service),
                disabledReason: 'Non riprogrammabile nello stato attuale.',
                onPressed: onReschedule,
              ),
              _ActionButton(
                label: service.operatorId == null ? 'Assegna' : 'Riassegna',
                icon: Icons.person_search_outlined,
                enabled: ServicePolicy.canReassign(service),
                disabledReason: 'Non riassegnabile nello stato attuale.',
                onPressed: onReassign,
              ),
              MenuAnchor(
                menuChildren: [
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.event_repeat, size: 18),
                    onPressed: ServicePolicy.canMarkToReschedule(service)
                        ? onMarkToReschedule
                        : null,
                    child: const Text('Segna da riprogrammare'),
                  ),
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.copy_all_outlined, size: 18),
                    onPressed: onDuplicate,
                    child: const Text('Duplica servizio'),
                  ),
                  const Divider(height: 8),
                  MenuItemButton(
                    leadingIcon: Icon(
                      Icons.cancel_outlined,
                      size: 18,
                      color: palette.danger,
                    ),
                    onPressed: ServicePolicy.canCancel(service)
                        ? onCancel
                        : null,
                    child: const Text('Annulla servizio'),
                  ),
                  Tooltip(
                    message: deleteBlocked ?? '',
                    child: MenuItemButton(
                      leadingIcon: Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: palette.danger,
                      ),
                      onPressed: deleteBlocked == null ? onDelete : null,
                      child: const Text('Elimina'),
                    ),
                  ),
                ],
                builder: (context, controller, _) => OutlinedButton.icon(
                  onPressed: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                  icon: const Icon(Icons.more_horiz, size: 18),
                  label: const Text('Altre azioni'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.disabledReason,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final String disabledReason;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final button = primary
        ? FilledButton.icon(
            onPressed: enabled ? onPressed : null,
            icon: Icon(icon, size: 18),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: enabled ? onPressed : null,
            icon: Icon(icon, size: 18),
            label: Text(label),
          );
    return enabled ? button : Tooltip(message: disabledReason, child: button);
  }
}

class _Alerts extends StatelessWidget {
  const _Alerts({required this.controller});

  final ServiceDetailController controller;

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final service = controller.service!;
    final now = deps.clock.now();
    final alerts = const ServiceAlertEvaluator()
        .evaluate(
          [service],
          now: now,
          operatorsById: deps.reference.operatorsById,
        )
        .where(
          (a) =>
              a.kind != ServiceAlertKind.sovrapposizione &&
              a.kind != ServiceAlertKind.richiestaModificaAperta,
        )
        .toList();
    final banners = <Widget>[
      for (final conflict in controller.conflicts)
        InlineBanner(
          style: severityStyle(context, NotificationSeverity.critica),
          title: 'Sovrapposizione con ${conflict.other(service.id).code}',
          message:
              '${deps.reference.operatorName(conflict.operatorId)} ha anche '
              '${conflict.other(service.id).kind.label} per '
              '${conflict.other(service.id).patient.fullName} '
              '(${Fmt.timeRange(conflict.other(service.id).scheduledStart, conflict.other(service.id).scheduledEnd)}).',
        ),
      for (final alert in alerts)
        InlineBanner(
          style: alertLevelStyle(context, alert.level),
          title: alert.kind.label,
          message: describeAlert(alert, now),
        ),
      if (controller.requests.any((r) => r.status.isOpen))
        InlineBanner(
          style: severityStyle(context, NotificationSeverity.attenzione),
          title: 'Richiesta di modifica da gestire',
          message:
              'L\'operatore ha segnalato: ${controller.requests.firstWhere((r) => r.status.isOpen).reason.label.toLowerCase()}.',
          action: TextButton(
            onPressed: () {
              final request = controller.requests.firstWhere(
                (r) => r.status.isOpen,
              );
              Navigator.of(context).pop();
              deps.navigation.go(
                AppSection.changeRequests,
                intent: ChangeRequestIntent(changeRequestId: request.id),
              );
            },
            child: const Text('Gestisci'),
          ),
        ),
    ];
    if (banners.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        children: [
          for (final banner in banners)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: banner),
        ],
      ),
    );
  }
}

class _DetailsTab extends StatelessWidget {
  const _DetailsTab({required this.controller});

  final ServiceDetailController controller;

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    final service = controller.service!;
    final patient = controller.patient;
    final operator = deps.reference.operator(service.operatorId);
    final delay = service.startDelay;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        const SectionLabel('Pianificazione'),
        InfoRow(
          label: 'Programmato',
          icon: Icons.event_outlined,
          value:
              '${Fmt.capitalize(Fmt.dayLong(service.scheduledStart))}, '
              '${Fmt.timeRange(service.scheduledStart, service.scheduledEnd)} '
              '(${Fmt.duration(service.scheduledDuration)})',
        ),
        InfoRow(
          label: 'Inizio effettivo',
          icon: Icons.play_circle_outline,
          child: service.actualStart == null
              ? Text(
                  'Non ancora avviato dall\'app',
                  style: TextStyle(color: palette.textMuted),
                )
              : Row(
                  children: [
                    Text(Fmt.dateTime(service.actualStart!)),
                    const SizedBox(width: 8),
                    if (delay != null)
                      TagChip(
                        Fmt.delay(delay),
                        color: delay.inMinutes > 10
                            ? palette.warning
                            : palette.success,
                      ),
                  ],
                ),
        ),
        InfoRow(
          label: 'Fine effettiva',
          icon: Icons.stop_circle_outlined,
          child: service.actualEnd == null
              ? Text(
                  service.status == ServiceStatus.inCorso
                      ? 'In corso'
                      : 'Non registrata',
                  style: TextStyle(color: palette.textMuted),
                )
              : Text(
                  '${Fmt.dateTime(service.actualEnd!)} · durata effettiva '
                  '${Fmt.duration(service.actualDuration!)}',
                ),
        ),
        if (service.statusReason != null)
          InfoRow(
            label: 'Motivo stato',
            icon: Icons.info_outline,
            value: service.statusReason,
          ),
        const SizedBox(height: 18),
        const SectionLabel('Paziente e luogo'),
        InfoRow(
          label: 'Paziente',
          icon: Icons.personal_injury_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                service.patient.fullName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (patient != null)
                DotSeparated([
                  patient.code,
                  if (patient.birthDate != null)
                    'nato/a il ${Fmt.date(patient.birthDate!)}',
                ])
              else if (service.patient is ManualServicePatient)
                Text(
                  'Dati inseriti manualmente (non in anagrafica)',
                  style: TextStyle(color: palette.textMuted, fontSize: 12.5),
                ),
              if (patient?.notes != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    patient!.notes!,
                    style: TextStyle(color: palette.info, fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
        InfoRow(
          label: 'Indirizzo',
          icon: Icons.place_outlined,
          value: service.address,
        ),
        InfoRow(
          label: 'Telefono',
          icon: Icons.call_outlined,
          value: service.phone ?? '',
        ),
        InfoRow(
          label: 'Indicazioni',
          icon: Icons.signpost_outlined,
          value: service.directions ?? '',
        ),
        const SizedBox(height: 18),
        const SectionLabel('Assegnazione'),
        InfoRow(
          label: 'Struttura',
          icon: Icons.apartment_outlined,
          value: deps.reference.facilityName(service.facilityId),
        ),
        InfoRow(
          label: 'Operatore',
          icon: Icons.badge_outlined,
          child: operator == null
              ? Text(
                  'Da assegnare',
                  style: TextStyle(
                    color: palette.warning,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : InkWell(
                  onTap: () =>
                      unawaited(showOperatorDetail(context, operator.id)),
                  child: Row(
                    children: [
                      InitialsAvatar(
                        initials: operator.initials,
                        colorKey: operator.id,
                        size: 30,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              operator.fullName,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            DotSeparated([
                              operator.qualification,
                              operator.code,
                              operator.phone,
                            ]),
                          ],
                        ),
                      ),
                      if (!operator.isAssignable)
                        OperatorStatusBadge(operator.status, dense: true),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 18),
        const SectionLabel('Note per l\'operatore'),
        Text(
          service.notes ?? 'Nessuna nota.',
          style: TextStyle(
            color: service.notes == null
                ? palette.textMuted
                : palette.textPrimary,
          ),
        ),
        const SizedBox(height: 18),
        const SectionLabel('Registrazione'),
        InfoRow(
          label: 'Creato',
          value: '${Fmt.dateTime(service.createdAt)} da ${service.createdBy}',
        ),
        InfoRow(
          label: 'Ultima modifica',
          value: '${Fmt.dateTime(service.updatedAt)} da ${service.updatedBy}',
        ),
        InfoRow(label: 'Versione', value: '${service.version}'),
      ],
    );
  }
}

class _DocumentsTab extends StatelessWidget {
  const _DocumentsTab({required this.controller, required this.onAdd});

  final ServiceDetailController controller;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Fogli firma, verbali e allegati del servizio.',
                  style: TextStyle(color: context.palette.textSecondary),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onAdd,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: const Text('Aggiungi documenti'),
              ),
            ],
          ),
        ),
        Expanded(
          child: DocumentList(
            documents: controller.documents,
            onChanged: controller.refresh,
            emptyTitle: 'Nessun documento per questo servizio',
            showOwner: false,
          ),
        ),
      ],
    );
  }
}

class _RequestsTab extends StatelessWidget {
  const _RequestsTab({required this.controller});

  final ServiceDetailController controller;

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    final requests = controller.requests;
    if (requests.isEmpty) {
      return const EmptyView(
        title: 'Nessuna richiesta di modifica',
        message: 'Le richieste inviate dall\'operatore dall\'app mobile compaiono qui.',
        icon: Icons.mark_chat_read_outlined,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: requests.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final request = requests[index];
        return AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    request.code,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  ChangeRequestStatusBadge(request.status, dense: true),
                  const SizedBox(width: 6),
                  TagChip(request.reason.label),
                  const Spacer(),
                  Text(
                    Fmt.relative(request.createdAt, deps.clock.now()),
                    style: TextStyle(color: palette.textMuted, fontSize: 12.5),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('"${request.message}"'),
              const SizedBox(height: 4),
              Text(
                '— ${request.operatorName}',
                style: TextStyle(color: palette.textSecondary, fontSize: 12.5),
              ),
              if (request.outcome != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Esito: ${request.outcome!.label}'
                  '${request.closedBy == null ? '' : ' (${request.closedBy})'}',
                  style: TextStyle(
                    color: palette.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (request.status.isOpen)
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: () {
                      Navigator.of(context).pop();
                      deps.navigation.go(
                        AppSection.changeRequests,
                        intent: ChangeRequestIntent(
                          changeRequestId: request.id,
                        ),
                      );
                    },
                    child: const Text('Gestisci richiesta'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.history});

  final List<AuditEntry> history;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const EmptyView(
        title: 'Nessuna attività registrata',
        icon: Icons.history,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: history.length,
      itemBuilder: (context, index) => HistoryEntryTile(
        entry: history[index],
        isLast: index == history.length - 1,
      ),
    );
  }
}

/// Voce della cronologia con linea temporale e modifiche ai campi.
class HistoryEntryTile extends StatelessWidget {
  const HistoryEntryTile({super.key, required this.entry, this.isLast = false});

  final AuditEntry entry;
  final bool isLast;

  static IconData iconFor(String action) => switch (action) {
    AuditActions.serviceCreated => Icons.add_circle_outline,
    AuditActions.serviceRescheduled => Icons.update,
    AuditActions.serviceReassigned => Icons.swap_horiz,
    AuditActions.serviceCancelled => Icons.cancel_outlined,
    AuditActions.serviceStarted => Icons.play_circle_outline,
    AuditActions.serviceCompleted => Icons.check_circle_outline,
    AuditActions.serviceNotExecuted => Icons.report_gmailerrorred_outlined,
    AuditActions.serviceMarkedToReschedule => Icons.event_repeat,
    AuditActions.documentUploaded ||
    AuditActions.documentReceived => Icons.description_outlined,
    AuditActions.documentReviewed => Icons.fact_check_outlined,
    AuditActions.changeRequestReceived => Icons.mark_chat_unread_outlined,
    AuditActions.changeRequestReplied => Icons.reply_outlined,
    AuditActions.changeRequestClosed => Icons.task_alt,
    _ => Icons.edit_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final actorColor = switch (entry.actorKind) {
      ActorKind.centrale => Theme.of(context).colorScheme.primary,
      ActorKind.operatore => palette.accent,
      ActorKind.sistema => palette.textMuted,
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: actorColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    iconFor(entry.action),
                    size: 17,
                    color: actorColor,
                  ),
                ),
                if (!isLast)
                  Expanded(child: Container(width: 2, color: palette.border)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          auditActionLabel(entry.action),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        Fmt.dateTime(entry.occurredAt),
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(entry.summary),
                  const SizedBox(height: 4),
                  Text(
                    '${entry.actorName} · ${entry.actorKind.label}',
                    style: TextStyle(color: actorColor, fontSize: 12.5),
                  ),
                  if (entry.changes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    FieldChangesTable(changes: entry.changes),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tabella "campo: prima → dopo".
class FieldChangesTable extends StatelessWidget {
  const FieldChangesTable({super.key, required this.changes});

  final List<FieldChange> changes;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: palette.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        children: [
          for (final change in changes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(
                      change.label,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: change.oldValue ?? '—',
                            style: TextStyle(
                              color: palette.textMuted,
                              decoration: change.oldValue == null
                                  ? null
                                  : TextDecoration.lineThrough,
                            ),
                          ),
                          const TextSpan(text: '  →  '),
                          TextSpan(
                            text: change.newValue ?? '—',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      style: const TextStyle(fontSize: 12.5),
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

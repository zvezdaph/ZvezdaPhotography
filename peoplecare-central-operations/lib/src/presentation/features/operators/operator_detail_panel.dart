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
import '../../shared/widgets/service_tile.dart';
import '../../shared/widgets/states.dart';
import '../../theme/app_palette.dart';
import '../../theme/status_styles.dart';
import '../documents/attachments.dart';
import '../documents/document_list.dart';
import '../service_detail/service_detail_panel.dart';
import 'operator_form_dialog.dart';

/// Apre la scheda dell'operatore nel pannello laterale.
Future<void> showOperatorDetail(BuildContext context, String operatorId) {
  return showSidePanel<void>(
    context,
    width: 760,
    builder: (_) => OperatorDetailPanel(operatorId: operatorId),
  );
}

class OperatorDetailController extends ScreenController {
  OperatorDetailController({
    required PeopleCareRepositories repositories,
    required this.operatorId,
    required this.now,
  }) : _repositories = repositories,
       super(
         events: repositories.events,
         topics: const {
           OperationalEventTopic.operatori,
           OperationalEventTopic.servizi,
           OperationalEventTopic.documenti,
         },
       );

  final PeopleCareRepositories _repositories;
  final String operatorId;
  final DateTime Function() now;

  Operator? operator;
  List<Service> upcoming = const [];
  List<Service> recent = const [];
  List<DocumentInfo> documents = const [];
  List<AuditEntry> activity = const [];

  @override
  Future<void> fetch() async {
    final current = now();
    final today = startOfDay(current);
    final results = await Future.wait<Object>([
      _repositories.operators.getOperator(operatorId),
      _repositories.services.searchServices(
        ServiceQuery(
          operator: AssignedTo(operatorId),
          range: DateRange(today, addDays(today, 8)),
        ),
        page: const PageRequest(pageSize: 200),
      ),
      _repositories.services.searchServices(
        ServiceQuery(
          operator: AssignedTo(operatorId),
          range: DateRange(addDays(today, -7), today),
          descending: true,
        ),
        page: const PageRequest(pageSize: 200),
      ),
      _repositories.documents.searchDocuments(
        DocumentQuery(
          ownerType: DocumentOwnerType.operatore,
          ownerId: operatorId,
        ),
        page: const PageRequest(pageSize: 100),
      ),
      _repositories.audit.searchAudit(
        AuditQuery(entityId: operatorId),
        page: const PageRequest(pageSize: 50),
      ),
    ]);
    operator = results[0] as Operator;
    upcoming = (results[1] as PagedResult<Service>).items;
    recent = (results[2] as PagedResult<Service>).items;
    documents = (results[3] as PagedResult<DocumentInfo>).items;
    activity = (results[4] as PagedResult<AuditEntry>).items;
  }
}

class OperatorDetailPanel extends StatefulWidget {
  const OperatorDetailPanel({super.key, required this.operatorId});

  final String operatorId;

  @override
  State<OperatorDetailPanel> createState() => _OperatorDetailPanelState();
}

class _OperatorDetailPanelState extends State<OperatorDetailPanel> {
  late final OperatorDetailController _controller;

  @override
  void initState() {
    super.initState();
    final deps = AppScope.of(context);
    _controller = OperatorDetailController(
      repositories: deps.repositories,
      operatorId: widget.operatorId,
      now: deps.clock.now,
    );
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _after(Future<Object?> action) async {
    final result = await action;
    if (result != null) await _controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final operator = _controller.operator;
        if (operator == null) {
          return _controller.error != null
              ? ErrorView(error: _controller.error!, onRetry: _controller.load)
              : const LoadingView(message: 'Caricamento operatore…');
        }
        return DefaultTabController(
          length: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(operator: operator, onAction: _after),
              RefreshingBar(
                visible: _controller.isLoading && _controller.hasLoaded,
              ),
              TabBar(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tabs: [
                  const Tab(text: 'Profilo'),
                  Tab(text: 'Servizi (${_controller.upcoming.length})'),
                  Tab(text: 'Documenti (${_controller.documents.length})'),
                  const Tab(text: 'Attività'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _ProfileTab(operator: operator, onAction: _after),
                    _ServicesTab(controller: _controller),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.tonalIcon(
                              onPressed: () => _after(
                                showUploadDocumentsDialog(
                                  context,
                                  owner: DocumentOwner(
                                    type: DocumentOwnerType.operatore,
                                    id: operator.id,
                                    label: operator.fullName,
                                  ),
                                  defaultCategory: DocumentCategory.certificato,
                                ).then((docs) => docs.isEmpty ? null : docs),
                              ),
                              icon: const Icon(
                                Icons.upload_file_outlined,
                                size: 18,
                              ),
                              label: const Text('Aggiungi documenti'),
                            ),
                          ),
                        ),
                        Expanded(
                          child: DocumentList(
                            documents: _controller.documents,
                            onChanged: _controller.refresh,
                            emptyTitle: 'Nessun documento dell\'operatore',
                            showOwner: false,
                          ),
                        ),
                      ],
                    ),
                    _ActivityTab(entries: _controller.activity),
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

class _Header extends StatelessWidget {
  const _Header({required this.operator, required this.onAction});

  final Operator operator;
  final Future<void> Function(Future<Object?> action) onAction;

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
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
              InitialsAvatar(
                initials: operator.initials,
                colorKey: operator.id,
                size: 52,
                muted: !operator.isAssignable,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      operator.code,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      operator.fullName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${operator.qualification} · ${deps.reference.facilityName(operator.primaryFacilityId)}',
                      style: TextStyle(color: palette.textSecondary),
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
              OperatorStatusBadge(operator.status),
              Pill(
                label: operator.account == null
                    ? 'Nessun account'
                    : 'Account: ${operator.account!.status.label.toLowerCase()}',
                style: accountStatusStyle(context, operator.account?.status),
              ),
              if (operator.secondaryFacilityIds.isNotEmpty)
                TagChip(
                  Fmt.count(
                    operator.facilityIds.length,
                    'struttura',
                    'strutture',
                  ),
                  icon: Icons.apartment_outlined,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: operator.status == OperatorStatus.disabilitato
                    ? null
                    : () => onAction(
                        showOperatorForm(context, existing: operator),
                      ),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Modifica'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  deps.navigation.go(
                    AppSection.calendar,
                    intent: CalendarDateIntent(
                      deps.clock.now(),
                      weekView: true,
                      operatorId: operator.id,
                    ),
                  );
                },
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: const Text('Calendario'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  deps.navigation.go(
                    AppSection.services,
                    intent: ServicesFilterIntent(operatorId: operator.id),
                  );
                },
                icon: const Icon(Icons.assignment_outlined, size: 18),
                label: const Text('Tutti i servizi'),
              ),
              MenuAnchor(
                menuChildren: [
                  if (operator.status != OperatorStatus.attivo)
                    MenuItemButton(
                      leadingIcon: const Icon(
                        Icons.play_arrow_outlined,
                        size: 18,
                      ),
                      onPressed: () => onAction(
                        showOperatorStatusDialog(
                          context,
                          operator,
                          OperatorStatus.attivo,
                        ),
                      ),
                      child: const Text('Riattiva'),
                    ),
                  if (operator.status == OperatorStatus.attivo)
                    MenuItemButton(
                      leadingIcon: const Icon(
                        Icons.pause_circle_outline,
                        size: 18,
                      ),
                      onPressed: () => onAction(
                        showOperatorStatusDialog(
                          context,
                          operator,
                          OperatorStatus.sospeso,
                        ),
                      ),
                      child: const Text('Sospendi…'),
                    ),
                  if (operator.status != OperatorStatus.disabilitato)
                    MenuItemButton(
                      leadingIcon: Icon(
                        Icons.block,
                        size: 18,
                        color: palette.danger,
                      ),
                      onPressed: () => onAction(
                        showOperatorStatusDialog(
                          context,
                          operator,
                          OperatorStatus.disabilitato,
                        ),
                      ),
                      child: const Text('Disabilita…'),
                    ),
                  const Divider(height: 8),
                  if (operator.account == null)
                    MenuItemButton(
                      leadingIcon: const Icon(Icons.link, size: 18),
                      onPressed: () =>
                          onAction(showLinkAccountDialog(context, operator)),
                      child: const Text('Collega account…'),
                    )
                  else
                    MenuItemButton(
                      leadingIcon: const Icon(Icons.link_off, size: 18),
                      onPressed: () =>
                          onAction(unlinkAccount(context, operator)),
                      child: const Text('Scollega account'),
                    ),
                ],
                builder: (context, controller, _) => OutlinedButton.icon(
                  onPressed: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                  icon: const Icon(Icons.more_horiz, size: 18),
                  label: const Text('Stato e account'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.operator, required this.onAction});

  final Operator operator;
  final Future<void> Function(Future<Object?> action) onAction;

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    final account = operator.account;
    Widget copyable(String value) => Row(
      children: [
        Flexible(child: SelectableText(value)),
        IconButton(
          tooltip: 'Copia',
          visualDensity: VisualDensity.compact,
          iconSize: 16,
          onPressed: () {
            unawaited(Clipboard.setData(ClipboardData(text: value)));
            showMessage(context, 'Copiato negli appunti');
          },
          icon: const Icon(Icons.copy),
        ),
      ],
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        if (!operator.isAssignable)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: InlineBanner(
              style: operatorStatusStyle(context, operator.status),
              title: 'Operatore ${operator.status.label.toLowerCase()}',
              message: operator.statusReason ?? 'Non assegnabile ai servizi.',
            ),
          ),
        const SectionLabel('Contatti'),
        InfoRow(
          label: 'Email',
          icon: Icons.alternate_email,
          child: copyable(operator.email),
        ),
        InfoRow(
          label: 'Telefono',
          icon: Icons.call_outlined,
          child: copyable(operator.phone),
        ),
        const SizedBox(height: 16),
        const SectionLabel('Strutture'),
        InfoRow(
          label: 'Principale',
          icon: Icons.apartment_outlined,
          value: deps.reference.facilityName(operator.primaryFacilityId),
        ),
        InfoRow(
          label: 'Aggiuntive',
          icon: Icons.add_business_outlined,
          value: operator.secondaryFacilityIds.isEmpty
              ? 'Nessuna'
              : operator.secondaryFacilityIds
                    .map(deps.reference.facilityName)
                    .join(', '),
        ),
        const SizedBox(height: 16),
        SectionLabel(
          'Account app mobile',
          trailing: account == null
              ? TextButton.icon(
                  onPressed: () =>
                      onAction(showLinkAccountDialog(context, operator)),
                  icon: const Icon(Icons.link, size: 17),
                  label: const Text('Collega'),
                )
              : null,
        ),
        if (account == null)
          Text(
            'Nessun account collegato: l\'operatore non può usare l\'app mobile.',
            style: TextStyle(color: palette.textMuted),
          )
        else ...[
          InfoRow(
            label: 'Nome utente',
            icon: Icons.person_outline,
            value: account.username,
          ),
          InfoRow(
            label: 'Stato account',
            icon: Icons.verified_user_outlined,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Pill(
                label: account.status.label,
                style: accountStatusStyle(context, account.status),
                dense: true,
              ),
            ),
          ),
          InfoRow(
            label: 'Collegato il',
            icon: Icons.event_outlined,
            value: account.linkedAt == null
                ? '—'
                : Fmt.dateTime(account.linkedAt!),
          ),
        ],
        InfoRow(
          label: 'Ultimo accesso',
          icon: Icons.login,
          value: operator.lastAccessAt == null
              ? 'Mai'
              : '${Fmt.dateTime(operator.lastAccessAt!)} '
                    '(${Fmt.relative(operator.lastAccessAt!, deps.clock.now())})',
        ),
        const SizedBox(height: 16),
        const SectionLabel('Note interne'),
        Text(
          operator.notes ?? 'Nessuna nota.',
          style: TextStyle(
            color: operator.notes == null ? palette.textMuted : null,
          ),
        ),
        const SizedBox(height: 16),
        const SectionLabel('Registrazione'),
        InfoRow(label: 'ID interno', value: operator.id),
        InfoRow(label: 'Creato il', value: Fmt.dateTime(operator.createdAt)),
        InfoRow(
          label: 'Ultima modifica',
          value:
              '${Fmt.dateTime(operator.updatedAt)} · versione ${operator.version}',
        ),
      ],
    );
  }
}

class _ServicesTab extends StatelessWidget {
  const _ServicesTab({required this.controller});

  final OperatorDetailController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    void open(Service s) => unawaited(showServiceDetail(context, s.id));
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: SectionLabel('Oggi e prossimi 7 giorni'),
        ),
        if (controller.upcoming.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              'Nessun servizio pianificato.',
              style: TextStyle(color: palette.textMuted),
            ),
          ),
        for (final service in controller.upcoming) ...[
          ServiceTile(
            service: service,
            showDate: true,
            onTap: () => open(service),
            subtitle:
                '${service.code} · ${context.deps.reference.facilityName(service.facilityId)}',
          ),
          Divider(height: 1, color: palette.border),
        ],
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: SectionLabel('Ultimi 7 giorni'),
        ),
        for (final service in controller.recent.take(40)) ...[
          ServiceTile(
            service: service,
            showDate: true,
            onTap: () => open(service),
            subtitle: service.actualStart == null
                ? service.code
                : '${service.code} · avvio ${Fmt.delay(service.startDelay!)}',
          ),
          Divider(height: 1, color: palette.border),
        ],
      ],
    );
  }
}

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({required this.entries});

  final List<AuditEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const EmptyView(title: 'Nessuna attività', icon: Icons.history);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: entries.length,
      itemBuilder: (context, index) => HistoryEntryTile(
        entry: entries[index],
        isLast: index == entries.length - 1,
      ),
    );
  }
}

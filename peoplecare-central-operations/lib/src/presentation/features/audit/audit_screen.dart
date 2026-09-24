import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/clock.dart';
import '../../../domain/domain.dart';
import '../../app_scope.dart';
import '../../app_state/screen_controller.dart';
import '../../app_state/section_activity.dart';
import '../../shared/csv.dart';
import '../../shared/formatters.dart';
import '../../shared/labels.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/data_table.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/filters.dart';
import '../../shared/widgets/layout.dart';
import '../../shared/widgets/states.dart';
import '../../theme/app_palette.dart';
import '../../theme/status_styles.dart';
import '../operators/operator_detail_panel.dart';
import '../service_detail/service_detail_panel.dart';

enum AuditPeriod {
  oggi('Oggi'),
  settimana('Ultimi 7 giorni'),
  mese('Ultimi 30 giorni'),
  tutto('Tutto');

  const AuditPeriod(this.label);

  final String label;

  DateRange? range(DateTime now) {
    final tomorrow = addDays(startOfDay(now), 1);
    return switch (this) {
      oggi => DateRange.day(now),
      settimana => DateRange(addDays(tomorrow, -7), tomorrow),
      mese => DateRange(addDays(tomorrow, -30), tomorrow),
      tutto => null,
    };
  }
}

class AuditController extends ScreenController {
  AuditController({
    required PeopleCareRepositories repositories,
    required this.clock,
  }) : _repositories = repositories,
       super(
         events: repositories.events,
         topics: const {
           OperationalEventTopic.servizi,
           OperationalEventTopic.operatori,
           OperationalEventTopic.documenti,
           OperationalEventTopic.richiesteModifica,
           OperationalEventTopic.strutture,
           OperationalEventTopic.tipologieServizio,
         },
         refreshDebounce: const Duration(seconds: 1),
       );

  final PeopleCareRepositories _repositories;
  final Clock clock;

  static const pageSize = 60;

  AuditPeriod period = AuditPeriod.settimana;
  Set<ActorKind> actorKinds = {};
  Set<AuditEntityType> entityTypes = {};
  String search = '';
  int page = 1;
  final Set<String> expanded = {};

  PagedResult<AuditEntry> result = const PagedResult(
    items: [],
    total: 0,
    page: 1,
    pageSize: pageSize,
  );

  AuditQuery get query => AuditQuery(
    range: period.range(clock.now()),
    actorKinds: actorKinds,
    entityTypes: entityTypes,
    search: search.isEmpty ? null : search,
  );

  @override
  Future<void> fetch() async {
    result = await _repositories.audit.searchAudit(
      query,
      page: PageRequest(page: page, pageSize: pageSize),
    );
  }

  Future<List<AuditEntry>> fetchAll() => fetchAllPages(
    (page) => _repositories.audit.searchAudit(query, page: page),
  );

  void _changed() {
    page = 1;
    unawaited(load());
  }

  void setPeriod(AuditPeriod value) {
    period = value;
    _changed();
  }

  void setActorKinds(Set<ActorKind> value) {
    actorKinds = value;
    _changed();
  }

  void setEntityTypes(Set<AuditEntityType> value) {
    entityTypes = value;
    _changed();
  }

  void setSearch(String value) {
    search = value;
    _changed();
  }

  void goToPage(int value) {
    page = value;
    unawaited(load());
  }

  void toggle(String id) {
    if (!expanded.remove(id)) expanded.add(id);
    notifySafely();
  }
}

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  late final AuditController _controller;

  @override
  void initState() {
    super.initState();
    final deps = AppScope.of(context);
    _controller = AuditController(
      repositories: deps.repositories,
      clock: deps.clock,
    );
    unawaited(_controller.load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.setActive(SectionActivity.of(context));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final deps = context.deps;
    final entries = await runGuarded(context, _controller.fetchAll);
    if (entries == null || !mounted) return;
    await saveCsv(
      context,
      fileName: timestampedFileName('registro_attivita', deps.clock.now()),
      bytes: buildCsv(
        [
          'Data e ora',
          'Attore',
          'Tipo attore',
          'Azione',
          'Elemento',
          'Riferimento',
          'Descrizione',
          'Modifiche',
        ],
        [
          for (final e in entries)
            [
              Fmt.dateTime(e.occurredAt),
              e.actorName,
              e.actorKind.label,
              auditActionLabel(e.action),
              e.entityType.label,
              e.entityLabel,
              e.summary,
              e.changes
                  .map(
                    (c) =>
                        '${c.label}: ${c.oldValue ?? '—'} → ${c.newValue ?? '—'}',
                  )
                  .join(' | '),
            ],
        ],
      ),
    );
  }

  void _openEntity(AuditEntry entry) {
    final serviceId = entry.serviceId;
    if (serviceId != null && entry.action != AuditActions.serviceDeleted) {
      unawaited(showServiceDetail(context, serviceId));
    } else if (entry.entityType == AuditEntityType.operatore) {
      unawaited(showOperatorDetail(context, entry.entityId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Registro attività',
              subtitle:
                  'Tracciabilità di ogni operazione della Centrale, degli '
                  'operatori (app mobile) e del sistema.',
              actions: [
                OutlinedButton.icon(
                  onPressed: () => unawaited(_export()),
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('Esporta CSV'),
                ),
              ],
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilterBar(
                      children: [
                        SearchField(
                          hint: 'Descrizione, elemento, persona…',
                          initialValue: c.search,
                          onChanged: c.setSearch,
                        ),
                        FilterMenu<AuditPeriod>(
                          label: 'Periodo',
                          icon: Icons.date_range_outlined,
                          allowAll: false,
                          value: c.period,
                          options: [
                            for (final p in AuditPeriod.values)
                              FilterOption(p, p.label),
                          ],
                          onChanged: (value) {
                            if (value != null) c.setPeriod(value);
                          },
                        ),
                        MultiFilterMenu<ActorKind>(
                          label: 'Chi',
                          icon: Icons.person_outline,
                          allLabel: 'Tutti',
                          values: c.actorKinds,
                          options: [
                            for (final kind in ActorKind.values)
                              FilterOption(kind, kind.label),
                          ],
                          onChanged: c.setActorKinds,
                        ),
                        MultiFilterMenu<AuditEntityType>(
                          label: 'Elemento',
                          icon: Icons.category_outlined,
                          allLabel: 'Tutti',
                          values: c.entityTypes,
                          options: [
                            for (final type in AuditEntityType.values)
                              if (type != AuditEntityType.sessione)
                                FilterOption(type, type.label),
                          ],
                          onChanged: c.setEntityTypes,
                        ),
                      ],
                    ),
                    Divider(height: 1, color: palette.border),
                    Expanded(
                      child: c.error != null && !c.hasLoaded
                          ? ErrorView(error: c.error!, onRetry: c.load)
                          : _table(context),
                    ),
                    PaginationBar(
                      result: c.result,
                      itemLabel: 'voci',
                      onPage: c.goToPage,
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

  Widget _table(BuildContext context) {
    final palette = context.palette;
    final c = _controller;
    return AppDataTable<AuditEntry>(
      items: c.result.items,
      idOf: (e) => e.id,
      isLoading: c.isLoading,
      rowHeight: 52,
      emptyTitle: 'Nessuna attività nel periodo',
      emptyIcon: Icons.history_toggle_off,
      expandedIds: c.expanded,
      onRowTap: (e) {
        if (e.changes.isNotEmpty) c.toggle(e.id);
      },
      expandedBuilder: (context, e) => Container(
        color: palette.surfaceMuted,
        padding: const EdgeInsets.fromLTRB(200, 4, 24, 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: FieldChangesTable(changes: e.changes),
          ),
        ),
      ),
      columns: [
        TableColumnDef(
          label: 'Data e ora',
          width: 170,
          cell: (context, e) => Text(
            Fmt.dateTime(e.occurredAt),
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        TableColumnDef(
          label: 'Chi',
          flex: 2,
          minWidth: 190,
          cell: (context, e) => Row(
            children: [
              Pill(
                label: e.actorKind.label,
                style: switch (e.actorKind) {
                  ActorKind.centrale => serviceStatusStyle(
                    context,
                    ServiceStatus.inCorso,
                  ),
                  ActorKind.operatore => serviceStatusStyle(
                    context,
                    ServiceStatus.assegnato,
                  ),
                  ActorKind.sistema => serviceStatusStyle(
                    context,
                    ServiceStatus.annullato,
                  ),
                },
                dense: true,
                showIcon: false,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.actorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        TableColumnDef(
          label: 'Azione',
          flex: 2,
          minWidth: 170,
          cell: (context, e) => Text(
            auditActionLabel(e.action),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        TableColumnDef(
          label: 'Elemento',
          flex: 2,
          minWidth: 170,
          cell: (context, e) => InkWell(
            onTap: () => _openEntity(e),
            child: CellText(e.entityLabel, secondary: e.entityType.label),
          ),
        ),
        TableColumnDef(
          label: 'Descrizione',
          flex: 5,
          minWidth: 280,
          cell: (context, e) =>
              Text(e.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        TableColumnDef(
          label: '',
          width: 48,
          cell: (context, e) => e.changes.isEmpty
              ? const SizedBox.shrink()
              : Tooltip(
                  message: Fmt.count(
                    e.changes.length,
                    'campo modificato',
                    'campi modificati',
                  ),
                  child: Icon(
                    c.expanded.contains(e.id)
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: palette.textSecondary,
                  ),
                ),
        ),
      ],
    );
  }
}

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
import '../../shared/widgets/filters.dart';
import '../../shared/widgets/layout.dart';
import '../../shared/widgets/states.dart';
import '../../theme/app_palette.dart';
import '../../theme/status_styles.dart';
import 'operator_detail_panel.dart';
import 'operator_form_dialog.dart';

/// Ordinamenti dell'elenco operatori.
enum OperatorSort { name, code, qualification, facility, status, lastAccess }

class OperatorsController extends ScreenController {
  OperatorsController({
    required PeopleCareRepositories repositories,
    required this.clock,
  }) : _repositories = repositories,
       super(
         events: repositories.events,
         topics: const {
           OperationalEventTopic.operatori,
           OperationalEventTopic.servizi,
         },
       );

  final PeopleCareRepositories _repositories;
  final Clock clock;

  String search = '';
  String? facilityId;
  Set<OperatorStatus> statuses = {
    OperatorStatus.attivo,
    OperatorStatus.sospeso,
  };
  String? qualification;
  OperatorSort sort = OperatorSort.name;
  bool descending = false;

  List<Operator> operators = const [];
  Map<String, int> servicesToday = const {};
  Set<String> onDuty = const {};

  @override
  Future<void> fetch() async {
    final results = await Future.wait<Object>([
      _repositories.operators.listOperators(
        OperatorQuery(
          search: search.isEmpty ? null : search,
          facilityId: facilityId,
          statuses: statuses,
          qualification: qualification,
        ),
      ),
      _repositories.services.listServicesInRange(DateRange.day(clock.now())),
    ]);
    operators = results[0] as List<Operator>;
    final today = results[1] as List<Service>;
    final counts = <String, int>{};
    final duty = <String>{};
    for (final service in today) {
      final id = service.operatorId;
      if (id == null || service.status == ServiceStatus.annullato) continue;
      counts[id] = (counts[id] ?? 0) + 1;
      if (service.status == ServiceStatus.inCorso) duty.add(id);
    }
    servicesToday = counts;
    onDuty = duty;
  }

  List<Operator> sorted(String Function(String? id) facilityName) {
    int compare(Operator a, Operator b) => switch (sort) {
      OperatorSort.name => a.sortName.compareTo(b.sortName),
      OperatorSort.code => a.code.compareTo(b.code),
      OperatorSort.qualification => a.qualification.compareTo(b.qualification),
      OperatorSort.facility => facilityName(
        a.primaryFacilityId,
      ).compareTo(facilityName(b.primaryFacilityId)),
      OperatorSort.status => a.status.index.compareTo(b.status.index),
      OperatorSort.lastAccess => (a.lastAccessAt ?? DateTime(1900)).compareTo(
        b.lastAccessAt ?? DateTime(1900),
      ),
    };
    final list = [...operators]..sort(compare);
    return descending ? list.reversed.toList() : list;
  }

  void setSearch(String value) {
    search = value;
    unawaited(load());
  }

  void setFacility(String? value) {
    facilityId = value;
    unawaited(load());
  }

  void setStatuses(Set<OperatorStatus> value) {
    statuses = value;
    unawaited(load());
  }

  void setQualification(String? value) {
    qualification = value;
    unawaited(load());
  }

  void setSort(OperatorSort value) {
    if (sort == value) {
      descending = !descending;
    } else {
      sort = value;
      descending = false;
    }
    notifySafely();
  }

  bool get hasFilters =>
      search.isNotEmpty ||
      facilityId != null ||
      qualification != null ||
      statuses.length != 2 ||
      !statuses.contains(OperatorStatus.attivo);

  void clearFilters() {
    search = '';
    facilityId = null;
    qualification = null;
    statuses = {OperatorStatus.attivo, OperatorStatus.sospeso};
    unawaited(load());
  }
}

class OperatorsScreen extends StatefulWidget {
  const OperatorsScreen({super.key});

  @override
  State<OperatorsScreen> createState() => _OperatorsScreenState();
}

class _OperatorsScreenState extends State<OperatorsScreen> {
  late final OperatorsController _controller;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    final deps = AppScope.of(context);
    _controller = OperatorsController(
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

  void _open(Operator operator) {
    setState(() => _selectedId = operator.id);
    unawaited(showOperatorDetail(context, operator.id));
  }

  Future<void> _create() async {
    final created = await showOperatorForm(context);
    if (created != null && mounted) {
      await _controller.refresh();
      if (mounted) _open(created);
    }
  }

  Future<void> _export() async {
    final deps = context.deps;
    final reference = deps.reference;
    final bytes = buildCsv(
      [
        'Codice',
        'Cognome',
        'Nome',
        'Qualifica',
        'Email',
        'Telefono',
        'Struttura principale',
        'Strutture aggiuntive',
        'Stato',
        'Account',
        'Ultimo accesso',
      ],
      [
        for (final o in _controller.sorted(reference.facilityName))
          [
            o.code,
            o.lastName,
            o.firstName,
            o.qualification,
            o.email,
            o.phone,
            reference.facilityName(o.primaryFacilityId),
            o.secondaryFacilityIds.map(reference.facilityName).join(', '),
            o.status.label,
            o.account == null
                ? 'Nessuno'
                : '${o.account!.username} (${o.account!.status.label})',
            o.lastAccessAt == null ? '' : Fmt.dateTime(o.lastAccessAt!),
          ],
      ],
    );
    await saveCsv(
      context,
      fileName: timestampedFileName('operatori', deps.clock.now()),
      bytes: bytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, deps.reference]),
      builder: (context, _) {
        final reference = deps.reference;
        final operators = _controller.sorted(reference.facilityName);
        final active = operators
            .where((o) => o.status == OperatorStatus.attivo)
            .length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Operatori PeopleCare',
              subtitle:
                  '${Fmt.count(operators.length, 'operatore visualizzato', 'operatori visualizzati')} · '
                  '${Fmt.count(active, 'attivo', 'attivi')} · '
                  '${_controller.onDuty.length} in servizio ora',
              actions: [
                OutlinedButton.icon(
                  onPressed: () => unawaited(_export()),
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('Esporta CSV'),
                ),
                FilledButton.icon(
                  onPressed: () => unawaited(_create()),
                  icon: const Icon(Icons.person_add_alt_1, size: 19),
                  label: const Text('Nuovo operatore'),
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
                      onClear: _controller.hasFilters
                          ? _controller.clearFilters
                          : null,
                      children: [
                        SearchField(
                          hint: 'Nome, codice, email, telefono…',
                          initialValue: _controller.search,
                          onChanged: _controller.setSearch,
                        ),
                        FilterMenu<String>(
                          label: 'Struttura',
                          icon: Icons.apartment_outlined,
                          allLabel: 'Tutte',
                          value: _controller.facilityId,
                          options: [
                            for (final facility in reference.facilities)
                              FilterOption(facility.id, facility.name),
                          ],
                          onChanged: _controller.setFacility,
                        ),
                        FilterMenu<String>(
                          label: 'Qualifica',
                          icon: Icons.badge_outlined,
                          allLabel: 'Tutte',
                          value: _controller.qualification,
                          options: [
                            for (final q in reference.qualifications)
                              FilterOption(q, q),
                          ],
                          onChanged: _controller.setQualification,
                        ),
                        MultiFilterMenu<OperatorStatus>(
                          label: 'Stato',
                          icon: Icons.verified_user_outlined,
                          values: _controller.statuses,
                          options: [
                            for (final status in OperatorStatus.values)
                              FilterOption(status, status.label),
                          ],
                          onChanged: _controller.setStatuses,
                        ),
                      ],
                    ),
                    Divider(height: 1, color: palette.border),
                    Expanded(
                      child: _controller.error != null && !_controller.hasLoaded
                          ? ErrorView(
                              error: _controller.error!,
                              onRetry: _controller.load,
                            )
                          : _table(context, operators),
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

  Widget _table(BuildContext context, List<Operator> operators) {
    final deps = context.deps;
    final palette = context.palette;
    final reference = deps.reference;
    final now = deps.clock.now();
    return AppDataTable<Operator>(
      items: operators,
      idOf: (o) => o.id,
      selectedId: _selectedId,
      isLoading: _controller.isLoading,
      onRowTap: _open,
      sortKey: _controller.sort,
      sortDescending: _controller.descending,
      onSort: (key) => _controller.setSort(key as OperatorSort),
      emptyTitle: 'Nessun operatore trovato',
      columns: [
        TableColumnDef(
          label: 'Codice',
          width: 120,
          sortKey: OperatorSort.code,
          cell: (context, o) =>
              Text(o.code, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        TableColumnDef(
          label: 'Operatore',
          flex: 3,
          minWidth: 220,
          sortKey: OperatorSort.name,
          cell: (context, o) => Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  InitialsAvatar(
                    initials: o.initials,
                    colorKey: o.id,
                    muted: !o.isAssignable,
                  ),
                  if (_controller.onDuty.contains(o.id))
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: StatusDot(
                        color: palette.success,
                        size: 11,
                        ring: palette.surface,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CellText(o.sortName, secondary: o.email, bold: true),
              ),
            ],
          ),
        ),
        TableColumnDef(
          label: 'Qualifica',
          flex: 2,
          minWidth: 130,
          sortKey: OperatorSort.qualification,
          cell: (context, o) => TagChip(o.qualification),
        ),
        TableColumnDef(
          label: 'Struttura principale',
          flex: 3,
          minWidth: 190,
          sortKey: OperatorSort.facility,
          cell: (context, o) => CellText(
            reference.facilityName(o.primaryFacilityId),
            secondary: o.secondaryFacilityIds.isEmpty
                ? null
                : '+ ${o.secondaryFacilityIds.map(reference.facilityName).join(', ')}',
          ),
        ),
        TableColumnDef(
          label: 'Telefono',
          width: 160,
          cell: (context, o) => Text(o.phone),
        ),
        TableColumnDef(
          label: 'Stato',
          width: 130,
          sortKey: OperatorSort.status,
          cell: (context, o) => OperatorStatusBadge(o.status, dense: true),
        ),
        TableColumnDef(
          label: 'Account',
          width: 150,
          cell: (context, o) => Pill(
            label: o.account == null ? 'Nessuno' : o.account!.status.label,
            style: accountStatusStyle(context, o.account?.status),
            dense: true,
          ),
        ),
        TableColumnDef(
          label: 'Ultimo accesso',
          width: 150,
          sortKey: OperatorSort.lastAccess,
          cell: (context, o) => Text(
            o.lastAccessAt == null ? 'Mai' : Fmt.relative(o.lastAccessAt!, now),
            style: TextStyle(
              color: o.lastAccessAt == null ? palette.textMuted : null,
            ),
          ),
        ),
        TableColumnDef(
          label: 'Oggi',
          width: 80,
          alignEnd: true,
          cell: (context, o) => Text(
            '${_controller.servicesToday[o.id] ?? 0}',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

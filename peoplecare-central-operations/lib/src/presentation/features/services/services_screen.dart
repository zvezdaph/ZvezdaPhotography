import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/domain.dart';
import '../../app_scope.dart';
import '../../app_state/navigation_controller.dart';
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
import '../service_actions/service_actions.dart';
import '../service_detail/service_detail_panel.dart';
import '../service_form/service_form_dialog.dart';
import 'services_controller.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  late final ServicesController _controller;
  late final NavigationController _navigation;
  String? _selectedId;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    final deps = AppScope.of(context);
    _controller = ServicesController(
      repositories: deps.repositories,
      clock: deps.clock,
    );
    _navigation = deps.navigation;
    _takeIntent();
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

  bool _takeIntent() {
    final intent = _navigation.takeIntent(AppSection.services);
    if (intent is! ServicesFilterIntent) return false;
    _controller.applyIntent(intent);
    final patientId = intent.patientId;
    if (patientId != null) unawaited(_resolvePatientLabel(patientId));
    return true;
  }

  Future<void> _resolvePatientLabel(String patientId) async {
    try {
      final patient = await context.deps.repositories.patients.getPatient(
        patientId,
      );
      if (!mounted) return;
      _controller.patientLabel = patient.fullName;
      _controller.notifySafely();
    } on RepositoryException {
      // L'etichetta resta generica.
    }
  }

  void _onNavigation() {
    if (_navigation.current != AppSection.services) return;
    if (_takeIntent()) unawaited(_controller.load());
  }

  void _open(Service service) {
    setState(() => _selectedId = service.id);
    unawaited(showServiceDetail(context, service.id));
  }

  Future<void> _newService() async {
    final created = await showServiceForm(context);
    if (created != null && mounted) {
      await _controller.refresh();
      if (mounted) _open(created);
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final deps = context.deps;
      final services = await _controller.fetchAll();
      final reference = deps.reference;
      final bytes = buildCsv(
        [
          'Codice',
          'Data',
          'Inizio programmato',
          'Fine programmata',
          'Inizio effettivo',
          'Fine effettiva',
          'Stato',
          'Priorità',
          'Tipologia',
          'Paziente',
          'Struttura',
          'Operatore',
          'Indirizzo',
          'Telefono',
          'Motivo stato',
        ],
        [
          for (final s in services)
            [
              s.code,
              Fmt.date(s.scheduledStart),
              Fmt.time(s.scheduledStart),
              Fmt.time(s.scheduledEnd),
              s.actualStart == null ? '' : Fmt.dateTime(s.actualStart!),
              s.actualEnd == null ? '' : Fmt.dateTime(s.actualEnd!),
              s.status.label,
              s.priority.label,
              s.kind.label,
              s.patient.fullName,
              reference.facilityName(s.facilityId),
              s.operatorId == null ? '' : reference.operatorName(s.operatorId),
              s.address,
              s.phone ?? '',
              s.statusReason ?? '',
            ],
        ],
      );
      if (!mounted) return;
      await saveCsv(
        context,
        fileName: timestampedFileName('servizi', deps.clock.now()),
        bytes: bytes,
      );
    } on RepositoryException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _pickPatient() async {
    final patient = await showDialog<Patient>(
      context: context,
      builder: (_) => const _PatientPickerDialog(),
    );
    if (patient != null) _controller.setPatient(patient.id, patient.fullName);
  }

  Future<void> _pickCustomRange() async {
    final now = context.deps.clock.now();
    final current = _controller.customRange;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2, 12, 31),
      initialDateRange: current == null
          ? null
          : DateTimeRange(start: current.start, end: addDays(current.end, -1)),
      locale: const Locale('it', 'IT'),
      saveText: 'Applica',
    );
    if (picked != null) {
      _controller.setDatePreset(
        DatePreset.personalizzato,
        custom: DateRange.days(picked.start, picked.end),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, deps.reference]),
      builder: (context, _) {
        final result = _controller.result;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Gestione servizi',
              subtitle:
                  'Ricerca, filtri e azioni su tutti i servizi pianificati.',
              actions: [
                OutlinedButton.icon(
                  onPressed: _exporting ? null : () => unawaited(_export()),
                  icon: _exporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('Esporta CSV'),
                ),
                FilledButton.icon(
                  onPressed: () => unawaited(_newService()),
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Nuovo servizio'),
                ),
              ],
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                decoration: BoxDecoration(
                  color: context.palette.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.palette.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _filters(context),
                    Divider(height: 1, color: context.palette.border),
                    Expanded(
                      child: _controller.error != null && !_controller.hasLoaded
                          ? ErrorView(
                              error: _controller.error!,
                              onRetry: _controller.load,
                            )
                          : _table(context),
                    ),
                    PaginationBar(
                      result: result,
                      itemLabel: 'servizi',
                      onPage: _controller.goToPage,
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

  Widget _filters(BuildContext context) {
    final deps = context.deps;
    final reference = deps.reference;
    final c = _controller;
    final operatorValue = switch (c.operator) {
      AssignedTo(:final operatorId) => operatorId,
      Unassigned() => '_none',
      null => null,
    };
    return FilterBar(
      onClear: c.hasFilters ? c.clearFilters : null,
      children: [
        SearchField(
          hint: 'Codice, paziente, indirizzo, note…',
          width: 290,
          initialValue: c.search,
          onChanged: c.setSearch,
        ),
        FilterMenu<DatePreset>(
          label: 'Data',
          icon: Icons.event_outlined,
          allowAll: false,
          value: c.datePreset,
          options: [
            for (final preset in DatePreset.values)
              FilterOption(
                preset,
                preset == DatePreset.personalizzato && c.customRange != null
                    ? '${Fmt.date(c.customRange!.start)} – '
                          '${Fmt.date(addDays(c.customRange!.end, -1))}'
                    : (preset == DatePreset.personalizzato
                          ? 'Personalizzato…'
                          : preset.label),
              ),
          ],
          onChanged: (value) {
            if (value == DatePreset.personalizzato) {
              unawaited(_pickCustomRange());
            } else if (value != null) {
              c.setDatePreset(value);
            }
          },
        ),
        FilterMenu<String>(
          label: 'Struttura',
          icon: Icons.apartment_outlined,
          allLabel: 'Tutte',
          value: c.facilityId,
          options: [
            for (final facility in reference.facilities)
              FilterOption(facility.id, facility.name),
          ],
          onChanged: c.setFacility,
        ),
        FilterMenu<String>(
          label: 'Operatore',
          icon: Icons.badge_outlined,
          allLabel: 'Tutti',
          value: operatorValue,
          options: [
            const FilterOption('_none', 'Non assegnati'),
            for (final operator in reference.operators)
              FilterOption(operator.id, operator.sortName),
          ],
          onChanged: (value) => c.setOperator(
            value == null
                ? null
                : (value == '_none' ? const Unassigned() : AssignedTo(value)),
          ),
        ),
        FilterButton(
          label: 'Paziente',
          icon: Icons.personal_injury_outlined,
          valueLabel:
              c.patientLabel ?? (c.patientId == null ? 'Tutti' : 'Selezionato'),
          active: c.patientId != null,
          onPressed: () {
            if (c.patientId != null) {
              c.setPatient(null, null);
            } else {
              unawaited(_pickPatient());
            }
          },
        ),
        FilterMenu<String>(
          label: 'Tipologia',
          icon: Icons.category_outlined,
          allLabel: 'Tutte',
          value: c.customTypeOnly ? '_custom' : c.serviceTypeId,
          options: [
            for (final type in reference.serviceTypes)
              FilterOption(type.id, type.name),
            const FilterOption('_custom', 'Servizi personalizzati'),
          ],
          onChanged: c.setType,
        ),
        MultiFilterMenu<ServiceStatus>(
          label: 'Stato',
          icon: Icons.flag_outlined,
          values: c.statuses,
          options: [
            for (final status in ServiceStatus.values)
              FilterOption(
                status,
                status.label,
                icon: serviceStatusStyle(context, status).icon,
                color: serviceStatusStyle(context, status).foreground,
              ),
          ],
          onChanged: c.setStatuses,
        ),
        MultiFilterMenu<ServicePriority>(
          label: 'Priorità',
          icon: Icons.low_priority,
          values: c.priorities,
          options: [
            for (final priority in ServicePriority.values.reversed)
              FilterOption(
                priority,
                priority.label,
                icon: priorityStyle(context, priority).icon,
                color: priorityStyle(context, priority).foreground,
              ),
          ],
          onChanged: c.setPriorities,
        ),
      ],
    );
  }

  Widget _table(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    final reference = deps.reference;
    final now = deps.clock.now();
    return AppDataTable<Service>(
      items: _controller.result.items,
      idOf: (s) => s.id,
      isLoading: _controller.isLoading,
      selectedId: _selectedId,
      onRowTap: _open,
      sortKey: _controller.sort,
      sortDescending: _controller.descending,
      onSort: (key) => _controller.setSort(key as ServiceSort),
      emptyTitle: 'Nessun servizio trovato',
      emptyMessage: 'Modifica i filtri o crea un nuovo servizio.',
      rowHeight: 56,
      rowAccent: (s) => switch (s.priority) {
        ServicePriority.urgente => palette.danger,
        ServicePriority.alta => palette.warning,
        _ => null,
      },
      columns: [
        TableColumnDef(
          label: 'Codice',
          width: 172,
          sortKey: ServiceSort.code,
          cell: (context, s) => Text(
            s.code,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        TableColumnDef(
          label: 'Data e orario',
          width: 205,
          sortKey: ServiceSort.scheduledStart,
          cell: (context, s) => CellText(
            '${Fmt.dayLabel(s.scheduledStart, now)} · ${Fmt.timeRange(s.scheduledStart, s.scheduledEnd)}',
            secondary: s.actualStart == null
                ? Fmt.date(s.scheduledStart)
                : 'Eff. ${Fmt.time(s.actualStart!)}'
                      '${s.actualEnd == null ? ' (in corso)' : '–${Fmt.time(s.actualEnd!)}'}',
          ),
        ),
        TableColumnDef(
          label: 'Paziente',
          flex: 3,
          minWidth: 160,
          sortKey: ServiceSort.patient,
          cell: (context, s) => CellText(
            s.patient.fullName,
            secondary: s.patient is ManualServicePatient
                ? 'Dati manuali · ${s.address}'
                : s.address,
            bold: true,
          ),
        ),
        TableColumnDef(
          label: 'Tipologia',
          flex: 2,
          minWidth: 140,
          cell: (context, s) => CellText(
            s.kind.label,
            secondary: s.isCustom ? 'Personalizzato' : null,
          ),
        ),
        TableColumnDef(
          label: 'Struttura',
          flex: 2,
          minWidth: 140,
          sortKey: ServiceSort.facility,
          cell: (context, s) => Text(
            reference.facilityName(s.facilityId),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TableColumnDef(
          label: 'Operatore',
          flex: 2,
          minWidth: 150,
          cell: (context, s) {
            final operator = reference.operator(s.operatorId);
            if (operator == null) {
              return Text(
                'Da assegnare',
                style: TextStyle(
                  color: palette.warning,
                  fontWeight: FontWeight.w600,
                ),
              );
            }
            return Row(
              children: [
                InitialsAvatar(
                  initials: operator.initials,
                  colorKey: operator.id,
                  size: 26,
                  muted: !operator.isAssignable,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    operator.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          },
        ),
        TableColumnDef(
          label: 'Priorità',
          width: 112,
          sortKey: ServiceSort.priority,
          cell: (context, s) => PriorityBadge(s.priority, dense: true),
        ),
        TableColumnDef(
          label: 'Stato',
          width: 160,
          sortKey: ServiceSort.status,
          cell: (context, s) => ServiceStatusBadge(s.status, dense: true),
        ),
        TableColumnDef(
          label: '',
          width: 64,
          cell: (context, s) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (s.documentCount > 0)
                Tooltip(
                  message: Fmt.count(s.documentCount, 'documento', 'documenti'),
                  child: Icon(
                    Icons.attach_file,
                    size: 17,
                    color: palette.textSecondary,
                  ),
                ),
              if (s.openChangeRequestCount > 0)
                Tooltip(
                  message: 'Richiesta di modifica aperta',
                  child: Icon(
                    Icons.mark_chat_unread_outlined,
                    size: 17,
                    color: palette.accent,
                  ),
                ),
            ],
          ),
        ),
        TableColumnDef(
          label: '',
          width: 52,
          cell: (context, s) => _RowMenu(
            service: s,
            onOpen: () => _open(s),
            onChanged: _controller.refresh,
          ),
        ),
      ],
    );
  }
}

class _RowMenu extends StatelessWidget {
  const _RowMenu({
    required this.service,
    required this.onOpen,
    required this.onChanged,
  });

  final Service service;
  final VoidCallback onOpen;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    Future<void> run(Future<Object?> action) async {
      final result = await action;
      if (result != null && result != false) await onChanged();
    }

    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.open_in_new, size: 18),
          onPressed: onOpen,
          child: const Text('Apri dettaglio'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.edit_outlined, size: 18),
          onPressed: ServicePolicy.canEdit(service)
              ? () => unawaited(run(ServiceActions.edit(context, service)))
              : null,
          child: const Text('Modifica'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.update, size: 18),
          onPressed: ServicePolicy.canReschedule(service)
              ? () =>
                    unawaited(run(ServiceActions.reschedule(context, service)))
              : null,
          child: const Text('Riprogramma'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.person_search_outlined, size: 18),
          onPressed: ServicePolicy.canReassign(service)
              ? () => unawaited(run(ServiceActions.reassign(context, service)))
              : null,
          child: Text(service.operatorId == null ? 'Assegna' : 'Riassegna'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.upload_file_outlined, size: 18),
          onPressed: () =>
              unawaited(run(ServiceActions.addDocuments(context, service))),
          child: const Text('Aggiungi documenti'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.copy_all_outlined, size: 18),
          onPressed: () =>
              unawaited(run(ServiceActions.duplicate(context, service))),
          child: const Text('Duplica'),
        ),
        const Divider(height: 8),
        MenuItemButton(
          leadingIcon: const Icon(Icons.cancel_outlined, size: 18),
          onPressed: ServicePolicy.canCancel(service)
              ? () => unawaited(run(ServiceActions.cancel(context, service)))
              : null,
          child: const Text('Annulla servizio'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.delete_outline, size: 18),
          onPressed: ServicePolicy.canDelete(service)
              ? () => unawaited(run(ServiceActions.delete(context, service)))
              : null,
          child: const Text('Elimina'),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: 'Azioni',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.more_vert),
      ),
    );
  }
}

class _PatientPickerDialog extends StatelessWidget {
  const _PatientPickerDialog();

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    return AppDialog(
      title: 'Filtra per paziente',
      icon: Icons.personal_injury_outlined,
      width: 560,
      child: SizedBox(
        height: 320,
        child: Align(
          alignment: Alignment.topCenter,
          child: Autocomplete<Patient>(
            displayStringForOption: (p) => '${p.fullName} (${p.code})',
            optionsBuilder: (value) async {
              if (value.text.trim().length < 2) {
                return const Iterable<Patient>.empty();
              }
              try {
                return await deps.repositories.patients.searchPatients(
                  value.text,
                  limit: 15,
                );
              } on RepositoryException {
                return const Iterable<Patient>.empty();
              }
            },
            onSelected: (patient) => Navigator.of(context).pop(patient),
            fieldViewBuilder: (context, controller, focus, onSubmit) =>
                TextField(
                  controller: controller,
                  focusNode: focus,
                  autofocus: true,
                  onSubmitted: (_) => onSubmit(),
                  decoration: const InputDecoration(
                    labelText: 'Nome, cognome o codice del paziente',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
          ),
        ),
      ),
    );
  }
}

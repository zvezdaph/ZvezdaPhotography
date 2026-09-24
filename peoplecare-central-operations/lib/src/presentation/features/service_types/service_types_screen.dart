import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/clock.dart';
import '../../../core/text.dart';
import '../../../domain/domain.dart';
import '../../app_scope.dart';
import '../../app_state/screen_controller.dart';
import '../../app_state/section_activity.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/data_table.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/filters.dart';
import '../../shared/widgets/form_fields.dart';
import '../../shared/widgets/layout.dart';
import '../../shared/widgets/states.dart';
import '../../theme/app_palette.dart';
import '../../theme/status_styles.dart';

class ServiceTypesController extends ScreenController {
  ServiceTypesController({
    required PeopleCareRepositories repositories,
    required this.clock,
  }) : _repositories = repositories,
       super(
         events: repositories.events,
         topics: const {OperationalEventTopic.tipologieServizio},
       );

  final PeopleCareRepositories _repositories;
  final Clock clock;

  List<ServiceType> types = const [];

  /// Utilizzo negli ultimi 30 giorni per tipologia.
  Map<String, int> usage = const {};
  String search = '';
  String? category;
  bool? active = true;

  @override
  Future<void> fetch() async {
    final now = clock.now();
    final results = await Future.wait<Object>([
      _repositories.serviceTypes.listServiceTypes(),
      _repositories.services.listServicesInRange(
        DateRange(addDays(startOfDay(now), -30), addDays(startOfDay(now), 1)),
      ),
    ]);
    types = results[0] as List<ServiceType>;
    final counts = <String, int>{};
    for (final service in results[1] as List<Service>) {
      final id = service.serviceTypeId;
      if (id != null) counts[id] = (counts[id] ?? 0) + 1;
    }
    usage = counts;
  }

  List<String> get categories =>
      {for (final t in types) t.category}.toList()..sort();

  List<ServiceType> get visible => types
      .where(
        (t) =>
            (active == null || t.isActive == active) &&
            (category == null || t.category == category) &&
            matchesSearch(search, [
              t.name,
              t.code,
              t.category,
              t.description,
              ...t.requiredQualifications,
            ]),
      )
      .toList();
}

class ServiceTypesScreen extends StatefulWidget {
  const ServiceTypesScreen({super.key});

  @override
  State<ServiceTypesScreen> createState() => _ServiceTypesScreenState();
}

class _ServiceTypesScreenState extends State<ServiceTypesScreen> {
  late final ServiceTypesController _controller;

  @override
  void initState() {
    super.initState();
    final deps = AppScope.of(context);
    _controller = ServiceTypesController(
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

  Future<void> _edit([ServiceType? type]) async {
    final saved = await showDialog<ServiceType>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ServiceTypeFormDialog(existing: type),
    );
    if (saved != null) await _controller.refresh();
  }

  Future<void> _toggleActive(ServiceType type) async {
    final draft = ServiceTypeDraft.fromServiceType(type);
    final updated = await runGuarded(
      context,
      () => context.deps.repositories.serviceTypes.updateServiceType(
        type.id,
        ServiceTypeDraft(
          name: draft.name,
          category: draft.category,
          defaultDurationMinutes: draft.defaultDurationMinutes,
          requiredQualifications: draft.requiredQualifications,
          description: draft.description,
          isActive: !type.isActive,
        ),
        expectedVersion: type.version,
      ),
      success: type.isActive
          ? '${type.name} disattivata: non sarà proponibile nei nuovi servizi'
          : '${type.name} riattivata',
    );
    if (updated != null) await _controller.refresh();
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
              title: 'Tipologie di servizio',
              subtitle:
                  'Catalogo usato nella creazione dei servizi: durata predefinita '
                  'e qualifiche adatte a svolgerli.',
              actions: [
                FilledButton.icon(
                  onPressed: () => unawaited(_edit()),
                  icon: const Icon(Icons.add, size: 19),
                  label: const Text('Nuova tipologia'),
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
                          hint: 'Nome, codice, qualifica…',
                          initialValue: c.search,
                          onChanged: (value) {
                            c.search = value;
                            c.notifySafely();
                          },
                        ),
                        FilterMenu<String>(
                          label: 'Area',
                          allLabel: 'Tutte',
                          value: c.category,
                          options: [
                            for (final category in c.categories)
                              FilterOption(category, category),
                          ],
                          onChanged: (value) {
                            c.category = value;
                            c.notifySafely();
                          },
                        ),
                        FilterMenu<bool>(
                          label: 'Stato',
                          allLabel: 'Tutte',
                          value: c.active,
                          options: const [
                            FilterOption(true, 'Attive'),
                            FilterOption(false, 'Non attive'),
                          ],
                          onChanged: (value) {
                            c.active = value;
                            c.notifySafely();
                          },
                        ),
                      ],
                    ),
                    Divider(height: 1, color: palette.border),
                    Expanded(
                      child: c.error != null && !c.hasLoaded
                          ? ErrorView(error: c.error!, onRetry: c.load)
                          : AppDataTable<ServiceType>(
                              items: c.visible,
                              idOf: (t) => t.id,
                              isLoading: c.isLoading,
                              onRowTap: (t) => unawaited(_edit(t)),
                              emptyTitle: 'Nessuna tipologia',
                              columns: [
                                TableColumnDef(
                                  label: 'Codice',
                                  width: 100,
                                  cell: (context, t) => Text(
                                    t.code,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                TableColumnDef(
                                  label: 'Tipologia',
                                  flex: 3,
                                  minWidth: 220,
                                  cell: (context, t) => CellText(
                                    t.name,
                                    secondary: t.description,
                                    bold: true,
                                  ),
                                ),
                                TableColumnDef(
                                  label: 'Area',
                                  flex: 2,
                                  minWidth: 150,
                                  cell: (context, t) => TagChip(
                                    t.category,
                                    color: colorForKey(context, t.category),
                                  ),
                                ),
                                TableColumnDef(
                                  label: 'Durata',
                                  width: 110,
                                  cell: (context, t) =>
                                      Text('${t.defaultDurationMinutes} min'),
                                ),
                                TableColumnDef(
                                  label: 'Qualifiche richieste',
                                  flex: 3,
                                  minWidth: 200,
                                  cell: (context, t) =>
                                      t.requiredQualifications.isEmpty
                                      ? Text(
                                          'Qualsiasi',
                                          style: TextStyle(
                                            color: palette.textMuted,
                                          ),
                                        )
                                      : Wrap(
                                          spacing: 4,
                                          runSpacing: 4,
                                          children: [
                                            for (final q
                                                in t.requiredQualifications)
                                              TagChip(q),
                                          ],
                                        ),
                                ),
                                TableColumnDef(
                                  label: 'Ultimi 30 gg',
                                  width: 120,
                                  alignEnd: true,
                                  cell: (context, t) =>
                                      Text('${c.usage[t.id] ?? 0} servizi'),
                                ),
                                TableColumnDef(
                                  label: 'Stato',
                                  width: 130,
                                  cell: (context, t) => Pill(
                                    label: t.isActive ? 'Attiva' : 'Non attiva',
                                    style: operatorStatusStyle(
                                      context,
                                      t.isActive
                                          ? OperatorStatus.attivo
                                          : OperatorStatus.disabilitato,
                                    ),
                                    dense: true,
                                  ),
                                ),
                                TableColumnDef(
                                  label: '',
                                  width: 150,
                                  cell: (context, t) => TextButton(
                                    onPressed: () =>
                                        unawaited(_toggleActive(t)),
                                    child: Text(
                                      t.isActive ? 'Disattiva' : 'Riattiva',
                                    ),
                                  ),
                                ),
                              ],
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

class _ServiceTypeFormDialog extends StatefulWidget {
  const _ServiceTypeFormDialog({this.existing});

  final ServiceType? existing;

  @override
  State<_ServiceTypeFormDialog> createState() => _ServiceTypeFormDialogState();
}

class _ServiceTypeFormDialogState extends State<_ServiceTypeFormDialog> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _category = TextEditingController(text: widget.existing?.category);
  late final _description = TextEditingController(
    text: widget.existing?.description,
  );
  late final _duration = TextEditingController(
    text: '${widget.existing?.defaultDurationMinutes ?? 60}',
  );
  late final Set<String> _qualifications = {
    ...?widget.existing?.requiredQualifications,
  };
  late bool _active = widget.existing?.isActive ?? true;
  Map<String, String> _errors = const {};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _category, _description, _duration]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final minutes = int.tryParse(_duration.text.trim());
    final errors = <String, String>{
      if (_name.text.trim().isEmpty) 'name': 'Obbligatorio.',
      if (_category.text.trim().isEmpty) 'category': 'Obbligatorio.',
      if (minutes == null || minutes < 5 || minutes > 720)
        'default_duration_minutes': 'Tra 5 e 720 minuti.',
    };
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    final draft = ServiceTypeDraft(
      name: _name.text.trim(),
      category: _category.text.trim(),
      defaultDurationMinutes: minutes!,
      requiredQualifications: _qualifications.toList(),
      description: emptyToNull(_description.text),
      isActive: _active,
    );
    setState(() => _saving = true);
    final repository = context.deps.repositories.serviceTypes;
    try {
      final existing = widget.existing;
      final saved = existing == null
          ? await repository.createServiceType(draft)
          : await repository.updateServiceType(
              existing.id,
              draft,
              expectedVersion: existing.version,
            );
      if (!mounted) return;
      Navigator.of(context).pop(saved);
      showMessage(context, 'Tipologia ${saved.name} salvata');
    } on ValidationException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errors = error.fieldErrors;
      });
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, error.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    return AppDialog(
      title: widget.existing == null
          ? 'Nuova tipologia di servizio'
          : 'Modifica ${widget.existing!.name}',
      subtitle:
          widget.existing?.code ?? 'Il codice viene assegnato dal sistema.',
      icon: Icons.category_outlined,
      width: 640,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _saving ? null : () => unawaited(_save()),
          child: const Text('Salva'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: requiredLabel('Nome'),
              errorText: _errors['name'],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _category,
                  decoration: InputDecoration(
                    labelText: requiredLabel('Area'),
                    hintText: 'Es. Assistenza di base, Sanitaria',
                    errorText: _errors['category'],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _duration,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: requiredLabel('Durata predefinita (min)'),
                    errorText: _errors['default_duration_minutes'],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Descrizione'),
          ),
          const SizedBox(height: 16),
          Text(
            'Qualifiche adatte (nessuna selezione = qualsiasi qualifica)',
            style: TextStyle(color: palette.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in deps.reference.qualifications)
                FilterChip(
                  label: Text(q),
                  selected: _qualifications.contains(q),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _qualifications.add(q);
                    } else {
                      _qualifications.remove(q);
                    }
                  }),
                ),
            ],
          ),
          if (_errors['required_qualifications'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _errors['required_qualifications']!,
                style: TextStyle(color: palette.danger, fontSize: 12.5),
              ),
            ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tipologia attiva'),
            subtitle: const Text(
              'Le tipologie non attive restano sui servizi esistenti ma non sono '
              'proposte per i nuovi.',
            ),
            value: _active,
            onChanged: (value) => setState(() => _active = value),
          ),
          if (widget.existing != null)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: SectionLabel('Nota'),
            ),
          if (widget.existing != null)
            Text(
              'Le modifiche valgono per i nuovi servizi; quelli esistenti mantengono '
              'il nome registrato.',
              style: TextStyle(color: palette.textMuted, fontSize: 12.5),
            ),
        ],
      ),
    );
  }
}

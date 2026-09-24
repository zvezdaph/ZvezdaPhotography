import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/clock.dart';
import '../../../domain/domain.dart';
import '../../app_scope.dart';
import '../../app_state/navigation_controller.dart';
import '../../app_state/screen_controller.dart';
import '../../app_state/section_activity.dart';
import '../../shared/labels.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/form_fields.dart';
import '../../shared/widgets/kpi.dart';
import '../../shared/widgets/layout.dart';
import '../../shared/widgets/states.dart';
import '../../theme/app_palette.dart';
import '../../theme/status_styles.dart';
import '../operators/operator_detail_panel.dart';

class FacilitiesController extends ScreenController {
  FacilitiesController({
    required PeopleCareRepositories repositories,
    required this.clock,
  }) : _repositories = repositories,
       super(
         events: repositories.events,
         topics: const {
           OperationalEventTopic.strutture,
           OperationalEventTopic.servizi,
           OperationalEventTopic.operatori,
         },
       );

  final PeopleCareRepositories _repositories;
  final Clock clock;

  List<Facility> facilities = const [];
  List<Operator> operators = const [];
  List<Service> today = const [];
  Map<String, int> toPlan = const {};

  @override
  Future<void> fetch() async {
    final now = clock.now();
    final day = startOfDay(now);
    final results = await Future.wait<Object>([
      _repositories.facilities.listFacilities(),
      _repositories.operators.listOperators(),
      _repositories.services.listServicesInRange(DateRange.day(now)),
      _repositories.services.listServicesInRange(
        DateRange(day, addDays(day, 8)),
      ),
    ]);
    facilities = results[0] as List<Facility>;
    operators = results[1] as List<Operator>;
    today = results[2] as List<Service>;
    final plan = <String, int>{};
    for (final service in results[3] as List<Service>) {
      if (!service.status.needsAttention) continue;
      plan[service.facilityId] = (plan[service.facilityId] ?? 0) + 1;
    }
    toPlan = plan;
  }
}

class FacilitiesScreen extends StatefulWidget {
  const FacilitiesScreen({super.key});

  @override
  State<FacilitiesScreen> createState() => _FacilitiesScreenState();
}

class _FacilitiesScreenState extends State<FacilitiesScreen> {
  late final FacilitiesController _controller;

  @override
  void initState() {
    super.initState();
    final deps = AppScope.of(context);
    _controller = FacilitiesController(
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

  Future<void> _edit([Facility? facility]) async {
    final saved = await showDialog<Facility>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FacilityFormDialog(existing: facility),
    );
    if (saved != null) await _controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Strutture',
              subtitle:
                  'Sedi operative PeopleCare. Gli operatori possono appartenere '
                  'a una struttura principale e ad altre strutture.',
              actions: [
                FilledButton.icon(
                  onPressed: () => unawaited(_edit()),
                  icon: const Icon(Icons.add_business_outlined, size: 19),
                  label: const Text('Nuova struttura'),
                ),
              ],
            ),
            RefreshingBar(
              visible: _controller.isLoading && _controller.hasLoaded,
            ),
            Expanded(
              child: !_controller.hasLoaded
                  ? (_controller.error != null
                        ? ErrorView(
                            error: _controller.error!,
                            onRetry: _controller.load,
                          )
                        : const LoadingView())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 1400
                            ? 3
                            : (constraints.maxWidth >= 900 ? 2 : 1);
                        const gap = 16.0;
                        final width =
                            (constraints.maxWidth - 48 - gap * (columns - 1)) /
                            columns;
                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                          child: Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: [
                              for (final facility in _controller.facilities)
                                SizedBox(
                                  width: width,
                                  child: _FacilityCard(
                                    facility: facility,
                                    controller: _controller,
                                    onEdit: () => unawaited(_edit(facility)),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _FacilityCard extends StatelessWidget {
  const _FacilityCard({
    required this.facility,
    required this.controller,
    required this.onEdit,
  });

  final Facility facility;
  final FacilitiesController controller;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    final primaryOps = controller.operators
        .where(
          (o) =>
              o.primaryFacilityId == facility.id &&
              o.status != OperatorStatus.disabilitato,
        )
        .toList();
    final secondaryOps = controller.operators
        .where(
          (o) =>
              o.secondaryFacilityIds.contains(facility.id) &&
              o.status != OperatorStatus.disabilitato,
        )
        .toList();
    final today = controller.today
        .where(
          (s) =>
              s.facilityId == facility.id &&
              s.status != ServiceStatus.annullato,
        )
        .toList();
    int count(ServiceStatus status) =>
        today.where((s) => s.status == status).length;
    Color statusColor(ServiceStatus status) =>
        serviceStatusStyle(context, status).foreground;
    final accent = colorForKey(context, facility.id);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 4, color: accent),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.apartment_outlined, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        facility.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          TagChip(facility.code),
                          TagChip(facility.kind.label, color: accent),
                          if (!facility.isActive)
                            Pill(
                              label: 'Non attiva',
                              style: operatorStatusStyle(
                                context,
                                OperatorStatus.disabilitato,
                              ),
                              dense: true,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Modifica',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoRow(
                  label: 'Indirizzo',
                  icon: Icons.place_outlined,
                  value: facility.fullAddress,
                  labelWidth: 110,
                ),
                InfoRow(
                  label: 'Contatti',
                  icon: Icons.call_outlined,
                  value: [
                    facility.phone ?? '',
                    facility.email ?? '',
                  ].where((v) => v.isNotEmpty).join(' · '),
                  labelWidth: 110,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Stat(
                  value: '${primaryOps.length}',
                  label: 'operatori',
                  caption: secondaryOps.isEmpty
                      ? null
                      : '+${secondaryOps.length} da altre strutture',
                ),
                _Stat(value: '${today.length}', label: 'servizi oggi'),
                _Stat(
                  value: '${controller.toPlan[facility.id] ?? 0}',
                  label: 'da pianificare',
                  color: (controller.toPlan[facility.id] ?? 0) > 0
                      ? palette.warning
                      : null,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
            child: SegmentedProgressBar(
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
                  statusColor(ServiceStatus.assegnato).withValues(alpha: 0.35),
                ),
                (
                  count(ServiceStatus.daAssegnare) +
                      count(ServiceStatus.daRiprogrammare),
                  statusColor(ServiceStatus.daAssegnare),
                ),
              ],
            ),
          ),
          if (primaryOps.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
              child: Wrap(
                spacing: -6,
                children: [
                  for (final operator in primaryOps.take(10))
                    Tooltip(
                      message:
                          '${operator.fullName} · ${operator.qualification}',
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () =>
                            unawaited(showOperatorDetail(context, operator.id)),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: palette.surface,
                              width: 2,
                            ),
                          ),
                          child: InitialsAvatar(
                            initials: operator.initials,
                            colorKey: operator.id,
                            size: 30,
                            muted: !operator.isAssignable,
                          ),
                        ),
                      ),
                    ),
                  if (primaryOps.length > 10)
                    Padding(
                      padding: const EdgeInsets.only(left: 12, top: 6),
                      child: Text('+${primaryOps.length - 10}'),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            // Wrap: su schede strette i pulsanti vanno a capo.
            child: Wrap(
              children: [
                TextButton.icon(
                  onPressed: () => deps.navigation.go(
                    AppSection.services,
                    intent: ServicesFilterIntent(
                      facilityId: facility.id,
                      range: DateRange.day(deps.clock.now()),
                    ),
                  ),
                  icon: const Icon(Icons.assignment_outlined, size: 18),
                  label: const Text('Servizi di oggi'),
                ),
                TextButton.icon(
                  onPressed: () => deps.navigation.go(
                    AppSection.services,
                    intent: ServicesFilterIntent(
                      facilityId: facility.id,
                      statuses: const {
                        ServiceStatus.daAssegnare,
                        ServiceStatus.daRiprogrammare,
                      },
                    ),
                  ),
                  icon: const Icon(Icons.person_search_outlined, size: 18),
                  label: const Text('Da pianificare'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    this.caption,
    this.color,
  });

  final String value;
  final String label;
  final String? caption;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: color ?? palette.textPrimary,
            ),
          ),
          Text(
            label,
            style: TextStyle(color: palette.textSecondary, fontSize: 12.5),
          ),
          if (caption != null)
            Text(
              caption!,
              style: TextStyle(color: palette.textMuted, fontSize: 11.5),
            ),
        ],
      ),
    );
  }
}

class _FacilityFormDialog extends StatefulWidget {
  const _FacilityFormDialog({this.existing});

  final Facility? existing;

  @override
  State<_FacilityFormDialog> createState() => _FacilityFormDialogState();
}

class _FacilityFormDialogState extends State<_FacilityFormDialog> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _address = TextEditingController(text: widget.existing?.address);
  late final _city = TextEditingController(text: widget.existing?.city);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _email = TextEditingController(text: widget.existing?.email);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late FacilityKind _kind =
      widget.existing?.kind ?? FacilityKind.servizioDomiciliare;
  late bool _active = widget.existing?.isActive ?? true;
  Map<String, String> _errors = const {};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _address, _city, _phone, _email, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final errors = <String, String>{
      if (_name.text.trim().isEmpty) 'name': 'Obbligatorio.',
      if (_address.text.trim().isEmpty) 'address': 'Obbligatorio.',
      if (_city.text.trim().isEmpty) 'city': 'Obbligatorio.',
    };
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    final draft = FacilityDraft(
      name: _name.text.trim(),
      kind: _kind,
      address: _address.text.trim(),
      city: _city.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      isActive: _active,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    setState(() => _saving = true);
    final repository = context.deps.repositories.facilities;
    try {
      final existing = widget.existing;
      final saved = existing == null
          ? await repository.createFacility(draft)
          : await repository.updateFacility(
              existing.id,
              draft,
              expectedVersion: existing.version,
            );
      if (!mounted) return;
      Navigator.of(context).pop(saved);
      showMessage(context, 'Struttura ${saved.name} salvata');
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
    return AppDialog(
      title: widget.existing == null ? 'Nuova struttura' : 'Modifica struttura',
      subtitle:
          widget.existing?.code ?? 'Il codice viene assegnato dal sistema.',
      icon: Icons.apartment_outlined,
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
          DropdownButtonFormField<FacilityKind>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Tipologia'),
            items: [
              for (final kind in FacilityKind.values)
                DropdownMenuItem(value: kind, child: Text(kind.label)),
            ],
            onChanged: (value) => setState(() => _kind = value ?? _kind),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _address,
                  decoration: InputDecoration(
                    labelText: requiredLabel('Indirizzo'),
                    errorText: _errors['address'],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _city,
                  decoration: InputDecoration(
                    labelText: requiredLabel('Comune'),
                    errorText: _errors['city'],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Telefono'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _email,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    errorText: _errors['email'],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Note'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Struttura attiva'),
            subtitle: const Text(
              'Le strutture non attive non sono selezionabili per nuovi servizi.',
            ),
            value: _active,
            onChanged: (value) => setState(() => _active = value),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/text.dart';
import '../../../domain/domain.dart';
import '../../app_scope.dart';
import '../../shared/formatters.dart';
import '../../shared/labels.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/form_fields.dart';
import '../../shared/widgets/layout.dart';
import '../../theme/app_palette.dart';
import '../../theme/status_styles.dart';
import '../documents/attachments.dart';
import '../service_actions/operator_picker.dart';

/// Valori iniziali per un nuovo servizio (es. dal calendario).
class ServiceFormPrefill {
  const ServiceFormPrefill({
    this.start,
    this.end,
    this.operatorId,
    this.facilityId,
  });

  final DateTime? start;
  final DateTime? end;
  final String? operatorId;
  final String? facilityId;
}

/// Crea, modifica o duplica un servizio. Restituisce il servizio salvato.
Future<Service?> showServiceForm(
  BuildContext context, {
  Service? existing,
  Service? duplicateOf,
  ServiceFormPrefill? prefill,
}) {
  return showDialog<Service>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ServiceFormDialog(
      existing: existing,
      duplicateOf: duplicateOf,
      prefill: prefill,
    ),
  );
}

class ServiceFormDialog extends StatefulWidget {
  const ServiceFormDialog({
    super.key,
    this.existing,
    this.duplicateOf,
    this.prefill,
  });

  final Service? existing;
  final Service? duplicateOf;
  final ServiceFormPrefill? prefill;

  @override
  State<ServiceFormDialog> createState() => _ServiceFormDialogState();
}

class _ServiceFormDialogState extends State<ServiceFormDialog> {
  bool _custom = false;
  String? _typeId;
  final _customName = TextEditingController();

  late DateTime _date;
  int? _start;
  int? _end;
  bool _endTouched = false;

  bool _manualPatient = false;
  Patient? _patient;
  RegisteredServicePatient? _registeredRef;
  final _manualFirst = TextEditingController();
  final _manualLast = TextEditingController();

  String? _facilityId;
  String? _operatorId;
  ServicePriority _priority = ServicePriority.normale;

  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _directions = TextEditingController();
  final _notes = TextEditingController();

  final List<PendingAttachment> _attachments = [];
  Map<String, String> _errors = const {};
  bool _saving = false;

  List<AssignmentCandidate>? _candidates;
  bool _loadingCandidates = false;
  Timer? _candidateDebounce;

  Service? get _source => widget.existing ?? widget.duplicateOf;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final source = _source;
    final now = context.deps.clock.now();
    if (source != null) {
      _fillFrom(source);
    } else {
      final prefill = widget.prefill;
      final start = prefill?.start ?? _nextQuarter(now);
      _date = startOfDay(start);
      _start = minutesSinceMidnight(start);
      final end = prefill?.end;
      _end = end == null
          ? _start! + 60
          : end.difference(startOfDay(start)).inMinutes;
      _endTouched = end != null;
      _operatorId = prefill?.operatorId;
      _facilityId =
          prefill?.facilityId ??
          context.deps.reference
              .operator(prefill?.operatorId)
              ?.primaryFacilityId;
    }
    _scheduleCandidates();
  }

  static DateTime _nextQuarter(DateTime now) {
    final rounded = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      (now.minute ~/ 15 + 1) * 15,
    );
    if (rounded.hour >= 20 || rounded.hour < 7) {
      final base = rounded.hour < 7 ? rounded : addDays(rounded, 1);
      return atTime(base, 8, 0);
    }
    return rounded;
  }

  void _fillFrom(Service source) {
    switch (source.kind) {
      case CatalogServiceKind(:final serviceTypeId):
        _custom = false;
        _typeId = serviceTypeId;
      case CustomServiceKind(:final name):
        _custom = true;
        _customName.text = name;
    }
    _date = startOfDay(source.scheduledStart);
    _start = minutesSinceMidnight(source.scheduledStart);
    _end = source.scheduledEnd.difference(_date).inMinutes;
    _endTouched = true;
    switch (source.patient) {
      case final RegisteredServicePatient registered:
        _manualPatient = false;
        _registeredRef = registered;
        unawaited(_loadPatient(registered.patientId));
      case ManualServicePatient(:final firstName, :final lastName):
        _manualPatient = true;
        _manualFirst.text = firstName;
        _manualLast.text = lastName;
    }
    _facilityId = source.facilityId;
    _operatorId = source.operatorId;
    _priority = source.priority;
    _address.text = source.address;
    _phone.text = source.phone ?? '';
    _directions.text = source.directions ?? '';
    _notes.text = source.notes ?? '';
  }

  Future<void> _loadPatient(String id) async {
    try {
      final patient = await context.deps.repositories.patients.getPatient(id);
      if (mounted) setState(() => _patient = patient);
    } on RepositoryException {
      // Resta il riferimento con il solo nome.
    }
  }

  @override
  void dispose() {
    _candidateDebounce?.cancel();
    for (final controller in [
      _customName,
      _manualFirst,
      _manualLast,
      _address,
      _phone,
      _directions,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Valori derivati
  // ---------------------------------------------------------------------------

  ServiceType? get _type => context.deps.reference.serviceType(_typeId);

  DateTime? get _startAt =>
      _start == null ? null : combineDateAndMinutes(_date, _start!);

  DateTime? get _endAt => _end == null
      ? null
      : combineDateAndMinutes(
          addDays(_date, _end! ~/ (24 * 60)),
          _end! % (24 * 60),
        );

  DateRange? get _slot {
    final start = _startAt;
    final end = _endAt;
    if (start == null || end == null || !end.isAfter(start)) return null;
    return DateRange(start, end);
  }

  AssignmentCandidate? get _selectedCandidate =>
      _candidates?.where((c) => c.operator.id == _operatorId).firstOrNull;

  // ---------------------------------------------------------------------------
  // Aggiornamenti
  // ---------------------------------------------------------------------------

  void _scheduleCandidates() {
    _candidateDebounce?.cancel();
    _candidateDebounce = Timer(
      const Duration(milliseconds: 300),
      _loadCandidates,
    );
  }

  Future<void> _loadCandidates() async {
    final slot = _slot;
    final facilityId = _facilityId;
    if (slot == null || facilityId == null) {
      if (mounted) setState(() => _candidates = null);
      return;
    }
    setState(() => _loadingCandidates = true);
    try {
      final candidates = await loadAssignmentCandidates(
        context.deps,
        slot: slot,
        facilityId: facilityId,
        requiredQualifications: _custom
            ? const []
            : (_type?.requiredQualifications ?? const []),
        excludeServiceId: widget.existing?.id,
      );
      if (mounted) setState(() => _candidates = candidates);
    } on RepositoryException {
      if (mounted) setState(() => _candidates = null);
    } finally {
      if (mounted) setState(() => _loadingCandidates = false);
    }
  }

  void _selectType(String? id) {
    setState(() {
      _typeId = id;
      final type = _type;
      if (type != null && _start != null && !_endTouched) {
        _end = _start! + type.defaultDurationMinutes;
      }
      _errors = {..._errors}..remove('service_type_id');
    });
    _scheduleCandidates();
  }

  void _setStart(int? minutes) {
    setState(() {
      if (minutes != null) {
        final duration = (_start != null && _end != null)
            ? _end! - _start!
            : (_type?.defaultDurationMinutes ?? 60);
        _end = minutes + duration;
      }
      _start = minutes;
      _errors = {..._errors}..remove('scheduled_end');
    });
    _scheduleCandidates();
  }

  void _setEnd(int? minutes) {
    setState(() {
      _endTouched = true;
      if (minutes == null) {
        _end = null;
      } else {
        _end = (_start != null && minutes <= _start!)
            ? minutes + 24 * 60
            : minutes;
      }
      _errors = {..._errors}..remove('scheduled_end');
    });
    _scheduleCandidates();
  }

  void _selectPatient(Patient patient) {
    final previousAddress = _patient?.fullAddress;
    final previousPhone = _patient?.phone;
    setState(() {
      _patient = patient;
      _registeredRef = RegisteredServicePatient(
        patientId: patient.id,
        firstName: patient.firstName,
        lastName: patient.lastName,
      );
      if (_address.text.trim().isEmpty || _address.text == previousAddress) {
        _address.text = patient.fullAddress ?? '';
      }
      if (_phone.text.trim().isEmpty || _phone.text == previousPhone) {
        _phone.text = patient.phone ?? '';
      }
      if (_facilityId == null && patient.facilityId != null) {
        _facilityId = patient.facilityId;
      }
      _errors = {..._errors}
        ..remove('patient')
        ..remove('address');
    });
    _scheduleCandidates();
  }

  Future<void> _addAttachments() async {
    final picked = await pickAttachments(context);
    if (!mounted || picked.isEmpty) return;
    setState(() => _attachments.addAll(picked));
  }

  Future<void> _chooseOperator() async {
    final slot = _slot;
    final facilityId = _facilityId;
    if (slot == null || facilityId == null) {
      setState(() {
        _errors = {
          ..._errors,
          'operator_id':
              'Indica struttura, data e orario per vedere le disponibilità.',
        };
      });
      return;
    }
    final choice = await showAssignOperatorDialog(
      context,
      slot: slot,
      facilityId: facilityId,
      requiredQualifications: _custom
          ? const []
          : (_type?.requiredQualifications ?? const []),
      currentOperatorId: _operatorId,
      excludeServiceId: widget.existing?.id,
      askReason: false,
      confirmLabel: 'Seleziona',
    );
    if (choice == null || !mounted) return;
    setState(() {
      _operatorId = choice.operatorId;
      _errors = {..._errors}..remove('operator_id');
    });
  }

  // ---------------------------------------------------------------------------
  // Salvataggio
  // ---------------------------------------------------------------------------

  Map<String, String> _validate() {
    final errors = <String, String>{};
    if (_custom) {
      if (_customName.text.trim().isEmpty) {
        errors['custom_type_name'] = 'Descrivi il servizio personalizzato.';
      }
    } else if (_typeId == null) {
      errors['service_type_id'] = 'Scegli la tipologia dal catalogo.';
    }
    final start = _startAt;
    final end = _endAt;
    if (start == null || end == null) {
      errors['scheduled_end'] = 'Indica ora di inizio e di fine.';
    } else {
      final scheduleError = ServicePolicy.validateSchedule(start, end);
      if (scheduleError != null) errors['scheduled_end'] = scheduleError;
    }
    if (_manualPatient) {
      if (_manualFirst.text.trim().isEmpty || _manualLast.text.trim().isEmpty) {
        errors['patient'] = 'Indica nome e cognome.';
      }
    } else if (_registeredRef == null) {
      errors['patient'] = 'Cerca e seleziona il paziente.';
    }
    if (_facilityId == null) errors['facility_id'] = 'Seleziona la struttura.';
    if (_address.text.trim().isEmpty) {
      errors['address'] = 'Indica l\'indirizzo.';
    }
    return errors;
  }

  ServiceDraft _buildDraft() {
    final ServiceKind kind = _custom
        ? CustomServiceKind(_customName.text.trim())
        : CatalogServiceKind(serviceTypeId: _typeId!, name: _type?.name ?? '');
    final ServicePatient patient = _manualPatient
        ? ManualServicePatient(
            firstName: _manualFirst.text.trim(),
            lastName: _manualLast.text.trim(),
          )
        : _registeredRef!;
    return ServiceDraft(
      kind: kind,
      scheduledStart: _startAt!,
      scheduledEnd: _endAt!,
      patient: patient,
      facilityId: _facilityId!,
      operatorId: _operatorId,
      priority: _priority,
      address: _address.text.trim(),
      phone: emptyToNull(_phone.text),
      directions: emptyToNull(_directions.text),
      notes: emptyToNull(_notes.text),
    );
  }

  Future<void> _save() async {
    final errors = _validate();
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    final deps = context.deps;
    final draft = _buildDraft();

    // Verifica finale delle sovrapposizioni dell'operatore scelto.
    final operatorId = _operatorId;
    if (operatorId != null) {
      final dayServices = await deps.repositories.services
          .listServicesInRange(DateRange.day(draft.scheduledStart))
          .catchError((Object _) => const <Service>[]);
      final overlaps = const ScheduleConflictDetector().overlapsForSlot(
        operatorId: operatorId,
        slot: DateRange(draft.scheduledStart, draft.scheduledEnd),
        services: dayServices,
        excludeServiceId: widget.existing?.id,
        now: deps.clock.now(),
      );
      if (!mounted) return;
      if (overlaps.isNotEmpty) {
        final proceed = await confirmAction(
          context,
          title: 'Sovrapposizione di orario',
          message:
              '${deps.reference.operatorName(operatorId)} ha già in quella fascia:\n'
              '${overlaps.map((s) => '• ${s.code} ${Fmt.timeRange(s.scheduledStart, s.scheduledEnd)} - ${s.patient.fullName}').join('\n')}\n\n'
              'Salvare comunque?',
          confirmLabel: 'Salva comunque',
          icon: Icons.warning_amber_rounded,
        );
        if (!proceed || !mounted) return;
      }
    }

    setState(() => _saving = true);
    try {
      final existing = widget.existing;
      final saved = existing == null
          ? await deps.repositories.services.createService(draft)
          : await deps.repositories.services.updateService(
              existing.id,
              draft,
              expectedVersion: existing.version,
            );
      var uploadErrors = const <String>[];
      if (_attachments.isNotEmpty) {
        final (_, errors) = await uploadAttachments(
          deps,
          DocumentOwner(
            type: DocumentOwnerType.servizio,
            id: saved.id,
            label: '${saved.code} - ${saved.patient.fullName}',
          ),
          _attachments,
        );
        uploadErrors = errors;
      }
      if (!mounted) return;
      Navigator.of(context).pop(saved);
      showMessage(
        context,
        uploadErrors.isEmpty
            ? (existing == null
                  ? 'Servizio ${saved.code} creato'
                  : 'Servizio ${saved.code} aggiornato')
            : 'Servizio salvato, ma alcuni allegati non sono stati caricati:\n'
                  '${uploadErrors.join('\n')}',
        error: uploadErrors.isNotEmpty,
      );
    } on ValidationException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errors = error.fieldErrors;
      });
      showMessage(context, error.message, error: true);
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, error.message, error: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Interfaccia
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final title = existing != null
        ? 'Modifica servizio ${existing.code}'
        : widget.duplicateOf != null
        ? 'Duplica servizio ${widget.duplicateOf!.code}'
        : 'Nuovo servizio';
    return AppDialog(
      title: title,
      subtitle: _isEdit
          ? 'Le modifiche vengono registrate nella cronologia del servizio.'
          : 'I campi con * sono obbligatori.',
      icon: _isEdit ? Icons.edit_outlined : Icons.add_task,
      width: 1080,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : () => unawaited(_save()),
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check, size: 18),
          label: Text(_isEdit ? 'Salva modifiche' : 'Crea servizio'),
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 820;
          final left = _leftColumn(context);
          final right = _rightColumn(context);
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
              const SizedBox(width: 24),
              Expanded(flex: 2, child: right),
            ],
          );
        },
      ),
    );
  }

  Widget _leftColumn(BuildContext context) {
    final reference = context.deps.reference;
    final types = reference.activeServiceTypes;
    final selectedType = _type;
    final typeOptions = [
      ...types,
      if (selectedType != null && !selectedType.isActive) selectedType,
    ];
    final slot = _slot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Tipologia'),
        ChoiceSegment<bool>(
          options: const [
            (false, 'Da catalogo', Icons.list_alt),
            (true, 'Personalizzato', Icons.edit_note),
          ],
          value: _custom,
          onChanged: (value) {
            setState(() => _custom = value);
            _scheduleCandidates();
          },
        ),
        const SizedBox(height: 10),
        if (!_custom)
          DropdownButtonFormField<String>(
            initialValue: _typeId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: requiredLabel('Tipologia di servizio'),
              errorText: _errors['service_type_id'],
            ),
            items: [
              for (final type in typeOptions)
                DropdownMenuItem(
                  value: type.id,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${type.name}${type.isActive ? '' : ' (non attiva)'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${type.category} · ${type.defaultDurationMinutes} min',
                        style: TextStyle(
                          color: context.palette.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: _selectType,
          )
        else
          TextField(
            controller: _customName,
            decoration: InputDecoration(
              labelText: requiredLabel('Descrizione del servizio'),
              hintText: 'Es. Supporto straordinario per trasloco',
              errorText: _errors['custom_type_name'],
            ),
            onChanged: (_) {
              if (_errors.containsKey('custom_type_name')) {
                setState(
                  () => _errors = {..._errors}..remove('custom_type_name'),
                );
              }
            },
          ),
        if (!_custom && selectedType?.requiredQualifications.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Qualifiche previste: ${selectedType!.requiredQualifications.join(', ')}',
              style: TextStyle(
                color: context.palette.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ),
        const SizedBox(height: 18),
        const SectionLabel('Data e orario'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: DateField(
                label: requiredLabel('Data'),
                value: _date,
                onChanged: (value) {
                  setState(() => _date = startOfDay(value));
                  _scheduleCandidates();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: TimeField(
                label: requiredLabel('Inizio'),
                value: _start,
                onChanged: _setStart,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: TimeField(
                label: requiredLabel('Fine'),
                value: _end == null ? null : _end! % (24 * 60),
                onChanged: _setEnd,
                errorText: _errors['scheduled_end'] == null ? null : ' ',
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            _errors['scheduled_end'] ??
                (slot == null
                    ? ''
                    : 'Durata ${Fmt.duration(slot.duration)} · ${Fmt.slot(slot.start, slot.end)}'),
            style: TextStyle(
              fontSize: 12.5,
              color: _errors['scheduled_end'] != null
                  ? context.palette.danger
                  : context.palette.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 18),
        const SectionLabel('Paziente'),
        ChoiceSegment<bool>(
          options: const [
            (false, 'Paziente registrato', Icons.person_search_outlined),
            (true, 'Dati manuali', Icons.edit_outlined),
          ],
          value: _manualPatient,
          onChanged: (value) => setState(() => _manualPatient = value),
        ),
        const SizedBox(height: 10),
        if (_manualPatient)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualFirst,
                  decoration: InputDecoration(
                    labelText: requiredLabel('Nome'),
                    errorText: _errors['patient'],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _manualLast,
                  decoration: InputDecoration(
                    labelText: requiredLabel('Cognome'),
                  ),
                ),
              ),
            ],
          )
        else ...[
          _PatientSearchField(
            errorText: _errors['patient'],
            onSelected: _selectPatient,
          ),
          if (_registeredRef != null) ...[
            const SizedBox(height: 10),
            _PatientCard(reference: _registeredRef!, patient: _patient),
          ],
        ],
        const SizedBox(height: 18),
        const SectionLabel('Luogo e contatti'),
        TextField(
          controller: _address,
          decoration: InputDecoration(
            labelText: requiredLabel('Indirizzo'),
            prefixIcon: const Icon(Icons.place_outlined, size: 19),
            errorText: _errors['address'],
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _phone,
          decoration: InputDecoration(
            labelText: 'Telefono di riferimento',
            prefixIcon: const Icon(Icons.call_outlined, size: 19),
            errorText: _errors['phone'],
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _directions,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Indicazioni per l\'accesso',
            hintText: 'Citofono, piano, chiavi, animali…',
            prefixIcon: Icon(Icons.signpost_outlined, size: 19),
          ),
        ),
        const SizedBox(height: 18),
        const SectionLabel('Note per l\'operatore'),
        TextField(
          controller: _notes,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Informazioni utili per svolgere il servizio',
          ),
        ),
      ],
    );
  }

  Widget _rightColumn(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    final facilities = [
      ...deps.reference.activeFacilities,
      if (_facilityId != null &&
          deps.reference.facility(_facilityId)?.isActive == false)
        deps.reference.facility(_facilityId)!,
    ];
    final operator = deps.reference.operator(_operatorId);
    final selected = _selectedCandidate;
    final suggestions = (_candidates ?? const <AssignmentCandidate>[])
        .where((c) => c.operator.id != _operatorId)
        .take(4)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Struttura e priorità'),
        DropdownButtonFormField<String>(
          initialValue: _facilityId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: requiredLabel('Struttura'),
            prefixIcon: const Icon(Icons.apartment_outlined, size: 19),
            errorText: _errors['facility_id'],
          ),
          items: [
            for (final facility in facilities)
              DropdownMenuItem(
                value: facility.id,
                child: Text(facility.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) {
            setState(() {
              _facilityId = value;
              _errors = {..._errors}..remove('facility_id');
            });
            _scheduleCandidates();
          },
        ),
        const SizedBox(height: 12),
        SegmentedButton<ServicePriority>(
          showSelectedIcon: false,
          segments: [
            for (final priority in ServicePriority.values)
              ButtonSegment(
                value: priority,
                label: Text(
                  priority.label,
                  style: TextStyle(
                    color: priority.rank >= ServicePriority.alta.rank
                        ? priorityStyle(context, priority).foreground
                        : null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
          selected: {_priority},
          onSelectionChanged: (value) =>
              setState(() => _priority = value.first),
        ),
        const SizedBox(height: 18),
        SectionLabel(
          'Operatore',
          trailing: _loadingCandidates
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _errors['operator_id'] != null
                  ? palette.danger
                  : palette.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (operator != null)
                    InitialsAvatar(
                      initials: operator.initials,
                      colorKey: operator.id,
                    )
                  else
                    Icon(
                      Icons.person_off_outlined,
                      color: palette.textMuted,
                      size: 30,
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          operator?.fullName ?? 'Nessun operatore',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          operator == null
                              ? 'Il servizio sarà "da assegnare"'
                              : '${operator.qualification} · ${operator.code}',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (operator != null)
                    IconButton(
                      tooltip: 'Non assegnare ora',
                      onPressed: () => setState(() => _operatorId = null),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                ],
              ),
              if (selected != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final (label, style) in candidateNotes(
                      context,
                      selected,
                    ))
                      Pill(label: label, style: style, dense: true),
                  ],
                ),
              ] else if (operator != null && !operator.isAssignable) ...[
                const SizedBox(height: 8),
                Pill(
                  label: 'Operatore ${operator.status.label.toLowerCase()}',
                  style: operatorStatusStyle(context, operator.status),
                  dense: true,
                ),
              ],
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => unawaited(_chooseOperator()),
                icon: const Icon(Icons.person_search_outlined, size: 18),
                label: Text(
                  operator == null ? 'Scegli operatore…' : 'Cambia operatore…',
                ),
              ),
              if (_errors['operator_id'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _errors['operator_id']!,
                    style: TextStyle(color: palette.danger, fontSize: 12.5),
                  ),
                ),
            ],
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Suggeriti per questa fascia',
            style: TextStyle(
              color: palette.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 6),
          for (final candidate in suggestions)
            _SuggestionRow(
              candidate: candidate,
              onSelect: () => setState(() {
                _operatorId = candidate.operator.id;
                _errors = {..._errors}..remove('operator_id');
              }),
            ),
        ],
        const SizedBox(height: 18),
        const SectionLabel('Documenti e allegati'),
        PendingAttachmentsEditor(
          attachments: _attachments,
          enabled: !_saving,
          onChanged: () => setState(() {}),
          onAdd: () => unawaited(_addAttachments()),
        ),
        if (_attachments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Gli allegati vengono caricati al salvataggio del servizio.',
              style: TextStyle(color: palette.textMuted, fontSize: 12),
            ),
          ),
        if (widget.existing != null) ...[
          const SizedBox(height: 18),
          const SectionLabel('Stato attuale'),
          Row(
            children: [
              ServiceStatusBadge(widget.existing!.status),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Versione ${widget.existing!.version} · ultima modifica '
                  '${Fmt.dateTime(widget.existing!.updatedAt)}',
                  style: TextStyle(color: palette.textMuted, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.candidate, required this.onSelect});

  final AssignmentCandidate candidate;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final operator = candidate.operator;
    final notes = candidateNotes(context, candidate);
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(6),
      hoverColor: palette.hover,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        child: Row(
          children: [
            InitialsAvatar(
              initials: operator.initials,
              colorKey: operator.id,
              size: 28,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    operator.fullName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    '${operator.qualification} · '
                    '${Fmt.count(candidate.servicesThatDay, 'servizio', 'servizi')} nel giorno',
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Pill(label: notes.first.$1, style: notes.first.$2, dense: true),
          ],
        ),
      ),
    );
  }
}

class _PatientSearchField extends StatelessWidget {
  const _PatientSearchField({required this.onSelected, this.errorText});

  final ValueChanged<Patient> onSelected;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    return LayoutBuilder(
      builder: (context, constraints) => Autocomplete<Patient>(
        displayStringForOption: (p) => '${p.fullName} (${p.code})',
        optionsBuilder: (value) async {
          final text = value.text.trim();
          if (text.length < 2) return const Iterable<Patient>.empty();
          try {
            return await deps.repositories.patients.searchPatients(
              text,
              limit: 12,
            );
          } on RepositoryException {
            return const Iterable<Patient>.empty();
          }
        },
        onSelected: onSelected,
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
            TextField(
              controller: controller,
              focusNode: focusNode,
              onSubmitted: (_) => onSubmitted(),
              decoration: InputDecoration(
                labelText: 'Cerca paziente (nome, cognome o codice) *',
                prefixIcon: const Icon(Icons.search, size: 19),
                errorText: errorText,
              ),
            ),
        optionsViewBuilder: (context, onSelect, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            color: palette.surface,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 300,
                maxWidth: constraints.maxWidth,
              ),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                children: [
                  for (final patient in options)
                    ListTile(
                      leading: const Icon(Icons.personal_injury_outlined),
                      title: Text('${patient.fullName} · ${patient.code}'),
                      subtitle: Text(
                        [
                          if (patient.birthDate != null)
                            'nato/a il ${Fmt.date(patient.birthDate!)}',
                          patient.fullAddress ?? '',
                          deps.reference.facilityName(patient.facilityId),
                        ].where((p) => p.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => onSelect(patient),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PatientCard extends StatelessWidget {
  const _PatientCard({required this.reference, required this.patient});

  final RegisteredServicePatient reference;
  final Patient? patient;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final p = patient;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InitialsAvatar(
            initials:
                '${reference.firstName.isEmpty ? '' : reference.firstName[0]}'
                '${reference.lastName.isEmpty ? '' : reference.lastName[0]}',
            colorKey: reference.patientId,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reference.fullName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (p != null) ...[
                  DotSeparated([
                    p.code,
                    if (p.birthDate != null)
                      'nato/a il ${Fmt.date(p.birthDate!)}',
                    context.deps.reference.facilityName(p.facilityId),
                  ]),
                  if (p.notes != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: palette.info,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              p.notes!,
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

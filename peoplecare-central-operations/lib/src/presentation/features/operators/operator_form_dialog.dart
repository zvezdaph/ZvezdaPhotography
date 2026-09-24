import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/domain.dart';
import '../../app_scope.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/form_fields.dart';
import '../../shared/widgets/layout.dart';
import '../../theme/app_palette.dart';

/// Crea o modifica un operatore. Restituisce l'operatore salvato.
Future<Operator?> showOperatorForm(BuildContext context, {Operator? existing}) {
  return showDialog<Operator>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _OperatorFormDialog(existing: existing),
  );
}

class _OperatorFormDialog extends StatefulWidget {
  const _OperatorFormDialog({this.existing});

  final Operator? existing;

  @override
  State<_OperatorFormDialog> createState() => _OperatorFormDialogState();
}

class _OperatorFormDialogState extends State<_OperatorFormDialog> {
  late final _firstName = TextEditingController(
    text: widget.existing?.firstName,
  );
  late final _lastName = TextEditingController(text: widget.existing?.lastName);
  late final _email = TextEditingController(text: widget.existing?.email);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _qualification = TextEditingController(
    text: widget.existing?.qualification,
  );
  late final _notes = TextEditingController(text: widget.existing?.notes);
  final _qualificationFocus = FocusNode();
  late String? _primaryFacilityId = widget.existing?.primaryFacilityId;
  late final Set<String> _secondary = {
    ...?widget.existing?.secondaryFacilityIds,
  };
  Map<String, String> _errors = const {};
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in [
      _firstName,
      _lastName,
      _email,
      _phone,
      _qualification,
      _notes,
    ]) {
      controller.dispose();
    }
    _qualificationFocus.dispose();
    super.dispose();
  }

  Map<String, String> _validate() {
    final errors = <String, String>{};
    if (_firstName.text.trim().isEmpty) errors['first_name'] = 'Obbligatorio.';
    if (_lastName.text.trim().isEmpty) errors['last_name'] = 'Obbligatorio.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim())) {
      errors['email'] = 'Email non valida.';
    }
    final digits = _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 6) errors['phone'] = 'Telefono non valido.';
    if (_qualification.text.trim().isEmpty) {
      errors['qualification'] = 'Indica la qualifica.';
    }
    if (_primaryFacilityId == null) {
      errors['primary_facility_id'] = 'Seleziona la struttura principale.';
    }
    return errors;
  }

  Future<void> _save() async {
    final errors = _validate();
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    final draft = OperatorDraft(
      firstName: _firstName.text.trim(),
      lastName: _lastName.text.trim(),
      email: _email.text.trim(),
      phone: _phone.text.trim(),
      qualification: _qualification.text.trim(),
      primaryFacilityId: _primaryFacilityId!,
      secondaryFacilityIds: _secondary
          .where((id) => id != _primaryFacilityId)
          .toList(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    setState(() => _saving = true);
    final repository = context.deps.repositories.operators;
    try {
      final existing = widget.existing;
      final saved = existing == null
          ? await repository.createOperator(draft)
          : await repository.updateOperator(
              existing.id,
              draft,
              expectedVersion: existing.version,
            );
      if (!mounted) return;
      Navigator.of(context).pop(saved);
      showMessage(
        context,
        existing == null
            ? 'Operatore ${saved.fullName} creato con codice ${saved.code}'
            : 'Dati di ${saved.fullName} aggiornati',
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

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    final existing = widget.existing;
    final facilities = deps.reference.facilities
        .where(
          (f) =>
              f.isActive ||
              f.id == _primaryFacilityId ||
              _secondary.contains(f.id),
        )
        .toList();
    return AppDialog(
      title: existing == null
          ? 'Nuovo operatore'
          : 'Modifica ${existing.fullName}',
      subtitle: existing == null
          ? 'Il codice operatore viene assegnato dal sistema al salvataggio.'
          : 'Codice ${existing.code}',
      icon: existing == null ? Icons.person_add_alt_1 : Icons.edit_outlined,
      width: 760,
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
          label: Text(existing == null ? 'Crea operatore' : 'Salva modifiche'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Anagrafica'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _firstName,
                  decoration: InputDecoration(
                    labelText: requiredLabel('Nome'),
                    errorText: _errors['first_name'],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _lastName,
                  decoration: InputDecoration(
                    labelText: requiredLabel('Cognome'),
                    errorText: _errors['last_name'],
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
                  controller: _email,
                  decoration: InputDecoration(
                    labelText: requiredLabel('Email'),
                    prefixIcon: const Icon(Icons.alternate_email, size: 19),
                    errorText: _errors['email'],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _phone,
                  decoration: InputDecoration(
                    labelText: requiredLabel('Telefono'),
                    prefixIcon: const Icon(Icons.call_outlined, size: 19),
                    errorText: _errors['phone'],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) => RawAutocomplete<String>(
              textEditingController: _qualification,
              focusNode: _qualificationFocus,
              optionsBuilder: (value) => deps.reference.qualifications.where(
                (q) => q.toLowerCase().contains(value.text.toLowerCase()),
              ),
              fieldViewBuilder: (context, controller, focus, onSubmit) =>
                  TextField(
                    controller: controller,
                    focusNode: focus,
                    decoration: InputDecoration(
                      labelText: requiredLabel('Qualifica / ruolo'),
                      hintText: 'Es. OSS, Infermiere, Fisioterapista',
                      prefixIcon: const Icon(Icons.badge_outlined, size: 19),
                      errorText: _errors['qualification'],
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
                      maxHeight: 240,
                      maxWidth: constraints.maxWidth,
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final option in options)
                          ListTile(
                            title: Text(option),
                            onTap: () => onSelect(option),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const SectionLabel('Strutture'),
          DropdownButtonFormField<String>(
            initialValue: _primaryFacilityId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: requiredLabel('Struttura principale'),
              prefixIcon: const Icon(Icons.apartment_outlined, size: 19),
              errorText: _errors['primary_facility_id'],
            ),
            items: [
              for (final facility in facilities)
                DropdownMenuItem(
                  value: facility.id,
                  child: Text(facility.name),
                ),
            ],
            onChanged: (value) => setState(() {
              _primaryFacilityId = value;
              _secondary.remove(value);
            }),
          ),
          const SizedBox(height: 12),
          Text(
            'Strutture aggiuntive (seconda struttura e successive)',
            style: TextStyle(color: palette.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final facility in facilities)
                if (facility.id != _primaryFacilityId)
                  FilterChip(
                    label: Text(facility.name),
                    selected: _secondary.contains(facility.id),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _secondary.add(facility.id);
                      } else {
                        _secondary.remove(facility.id);
                      }
                    }),
                  ),
            ],
          ),
          if (_errors['secondary_facility_ids'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _errors['secondary_facility_ids']!,
                style: TextStyle(color: palette.danger, fontSize: 12.5),
              ),
            ),
          const SizedBox(height: 20),
          const SectionLabel('Note interne'),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText:
                  'Disponibilità, competenze, indicazioni per la Centrale',
            ),
          ),
          if (existing == null) ...[
            const SizedBox(height: 16),
            Text(
              'Dopo il salvataggio potrai collegare l\'account per l\'app mobile '
              'dalla scheda dell\'operatore.',
              style: TextStyle(color: palette.textMuted, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// Cambio di stato (attivo / sospeso / disabilitato) con motivo.
Future<Operator?> showOperatorStatusDialog(
  BuildContext context,
  Operator operator,
  OperatorStatus target,
) async {
  final deps = context.deps;
  if (target == OperatorStatus.attivo) {
    final confirmed = await confirmAction(
      context,
      title: 'Riattivare ${operator.fullName}?',
      message: 'L\'operatore tornerà assegnabile ai servizi.',
      confirmLabel: 'Riattiva',
    );
    if (!confirmed || !context.mounted) return null;
    return runGuarded(
      context,
      () => deps.repositories.operators.changeStatus(
        operator.id,
        OperatorStatus.attivo,
        expectedVersion: operator.version,
      ),
      success: '${operator.fullName} è di nuovo attivo',
    );
  }
  final suspended = target == OperatorStatus.sospeso;
  final reason = await askText(
    context,
    title: suspended
        ? 'Sospendi ${operator.fullName}'
        : 'Disabilita ${operator.fullName}',
    message: suspended
        ? 'L\'operatore non potrà ricevere nuovi servizi finché non viene '
              'riattivato. I servizi già assegnati vanno riassegnati.'
        : 'L\'operatore resta nello storico ma non sarà più utilizzabile.',
    label: 'Motivo',
    confirmLabel: suspended ? 'Sospendi' : 'Disabilita',
    destructive: true,
    suggestions: suspended
        ? const ['Ferie', 'Malattia', 'Congedo', 'Verifica documentazione']
        : const ['Cessato rapporto di collaborazione', 'Trasferimento'],
  );
  if (reason == null || !context.mounted) return null;
  return runGuarded(
    context,
    () => deps.repositories.operators.changeStatus(
      operator.id,
      target,
      reason: reason,
      expectedVersion: operator.version,
    ),
    success: suspended
        ? '${operator.fullName} sospeso'
        : '${operator.fullName} disabilitato',
  );
}

/// Collega un account PeopleCare all'operatore.
Future<Operator?> showLinkAccountDialog(
  BuildContext context,
  Operator operator,
) async {
  final username = await askText(
    context,
    title: 'Collega account',
    message:
        'Indica il nome utente PeopleCare (email aziendale). L\'operatore '
        'riceverà l\'invito per il primo accesso all\'app mobile.',
    label: 'Nome utente',
    confirmLabel: 'Collega e invia invito',
    initialValue: operator.email,
    maxLines: 1,
  );
  if (username == null || !context.mounted) return null;
  return runGuarded(
    context,
    () => context.deps.repositories.operators.linkAccount(
      operator.id,
      username: username,
      expectedVersion: operator.version,
    ),
    success: 'Account collegato: invito inviato a $username',
  );
}

Future<Operator?> unlinkAccount(BuildContext context, Operator operator) async {
  final confirmed = await confirmAction(
    context,
    title: 'Scollegare l\'account?',
    message:
        '${operator.fullName} non potrà più accedere all\'app mobile con '
        '${operator.account?.username}.',
    confirmLabel: 'Scollega',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return null;
  return runGuarded(
    context,
    () => context.deps.repositories.operators.unlinkAccount(
      operator.id,
      expectedVersion: operator.version,
    ),
    success: 'Account scollegato',
  );
}

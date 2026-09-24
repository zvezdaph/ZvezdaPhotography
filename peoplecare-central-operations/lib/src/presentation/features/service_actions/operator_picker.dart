import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/text.dart';
import '../../../domain/domain.dart';
import '../../app_scope.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/layout.dart';
import '../../shared/widgets/states.dart';
import '../../theme/app_palette.dart';
import '../../theme/status_styles.dart';

/// Candidati per una fascia oraria, ordinati per idoneità.
Future<List<AssignmentCandidate>> loadAssignmentCandidates(
  AppDependencies deps, {
  required DateRange slot,
  required String facilityId,
  List<String> requiredQualifications = const [],
  String? excludeServiceId,
}) async {
  final dayServices = await deps.repositories.services.listServicesInRange(
    DateRange(
      startOfDay(slot.start),
      addDays(startOfDay(slot.end.subtract(const Duration(minutes: 1))), 1),
    ),
  );
  return const AssignmentAdvisor().rank(
    operators: deps.reference.visibleOperators,
    services: dayServices,
    slot: slot,
    facilityId: facilityId,
    requiredQualifications: requiredQualifications,
    excludeServiceId: excludeServiceId,
    now: deps.clock.now(),
  );
}

/// Avvertenze leggibili su un candidato.
List<(String, StatusStyle)> candidateNotes(
  BuildContext context,
  AssignmentCandidate candidate,
) {
  final palette = context.palette;
  StatusStyle tone(Color color, IconData icon) => StatusStyle(
    foreground: color,
    background: color.withValues(alpha: 0.1),
    border: color.withValues(alpha: 0.3),
    icon: icon,
  );
  return [
    if (candidate.isFree)
      ('Disponibile', tone(palette.success, Icons.check_circle_outline))
    else
      for (final other in candidate.overlapping)
        (
          'Sovrapposto a ${other.code} (${Fmt.timeRange(other.scheduledStart, other.scheduledEnd)})',
          tone(palette.danger, Icons.warning_amber_rounded),
        ),
    if (!candidate.belongsToFacility)
      ('Altra struttura', tone(palette.warning, Icons.apartment_outlined)),
    if (!candidate.qualificationMatches)
      ('Qualifica non prevista', tone(palette.warning, Icons.badge_outlined)),
  ];
}

/// Riga di un candidato selezionabile.
class CandidateTile extends StatelessWidget {
  const CandidateTile({
    super.key,
    required this.candidate,
    required this.selected,
    required this.onTap,
    this.isCurrent = false,
  });

  final AssignmentCandidate candidate;
  final bool selected;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final operator = candidate.operator;
    final primary = Theme.of(context).colorScheme.primary;
    final facility = context.deps.reference.facility(
      operator.primaryFacilityId,
    );
    return Material(
      color: selected ? primary.withValues(alpha: 0.08) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        hoverColor: palette.hover,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? primary.withValues(alpha: 0.6) : palette.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20,
                color: selected ? primary : palette.textMuted,
              ),
              const SizedBox(width: 10),
              InitialsAvatar(
                initials: operator.initials,
                colorKey: operator.id,
                size: 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            operator.fullName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: 6),
                          TagChip('Attuale', color: primary),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    DotSeparated([
                      operator.qualification,
                      operator.code,
                      facility?.name ?? '',
                      '${Fmt.count(candidate.servicesThatDay, 'servizio', 'servizi')} · '
                          '${Fmt.duration(candidate.plannedThatDay)} nel giorno',
                    ]),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final (label, style) in candidateNotes(
                          context,
                          candidate,
                        ))
                          Pill(label: label, style: style, dense: true),
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
  }
}

/// Esito del dialogo di assegnazione.
class AssignmentChoice {
  const AssignmentChoice({required this.operatorId, this.reason});

  /// `null` = rimuovere l'assegnazione.
  final String? operatorId;
  final String? reason;
}

/// Dialogo per scegliere l'operatore di una fascia oraria, con suggerimenti.
Future<AssignmentChoice?> showAssignOperatorDialog(
  BuildContext context, {
  required DateRange slot,
  required String facilityId,
  List<String> requiredQualifications = const [],
  String? currentOperatorId,
  String? excludeServiceId,
  String title = 'Assegna operatore',
  String? subtitle,
  bool allowUnassign = true,
  bool askReason = true,
  String confirmLabel = 'Assegna',
}) {
  return showDialog<AssignmentChoice>(
    context: context,
    builder: (_) => _AssignOperatorDialog(
      slot: slot,
      facilityId: facilityId,
      requiredQualifications: requiredQualifications,
      currentOperatorId: currentOperatorId,
      excludeServiceId: excludeServiceId,
      title: title,
      subtitle: subtitle,
      allowUnassign: allowUnassign,
      askReason: askReason,
      confirmLabel: confirmLabel,
    ),
  );
}

class _AssignOperatorDialog extends StatefulWidget {
  const _AssignOperatorDialog({
    required this.slot,
    required this.facilityId,
    required this.requiredQualifications,
    required this.currentOperatorId,
    required this.excludeServiceId,
    required this.title,
    required this.subtitle,
    required this.allowUnassign,
    required this.askReason,
    required this.confirmLabel,
  });

  final DateRange slot;
  final String facilityId;
  final List<String> requiredQualifications;
  final String? currentOperatorId;
  final String? excludeServiceId;
  final String title;
  final String? subtitle;
  final bool allowUnassign;
  final bool askReason;
  final String confirmLabel;

  @override
  State<_AssignOperatorDialog> createState() => _AssignOperatorDialogState();
}

class _AssignOperatorDialogState extends State<_AssignOperatorDialog> {
  List<AssignmentCandidate>? _candidates;
  Object? _error;
  String? _selected;
  String _search = '';
  bool _facilityOnly = false;
  final _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected = widget.currentOperatorId;
    unawaited(_load());
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final candidates = await loadAssignmentCandidates(
        context.deps,
        slot: widget.slot,
        facilityId: widget.facilityId,
        requiredQualifications: widget.requiredQualifications,
        excludeServiceId: widget.excludeServiceId,
      );
      if (mounted) setState(() => _candidates = candidates);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final reference = context.deps.reference;
    final candidates = (_candidates ?? const <AssignmentCandidate>[])
        .where(
          (c) =>
              (!_facilityOnly || c.belongsToFacility) &&
              matchesSearch(_search, [
                c.operator.firstName,
                c.operator.lastName,
                c.operator.code,
                c.operator.qualification,
              ]),
        )
        .toList();
    final changed = _selected != widget.currentOperatorId;
    return AppDialog(
      title: widget.title,
      subtitle:
          widget.subtitle ??
          '${Fmt.slot(widget.slot.start, widget.slot.end)} · '
              '${reference.facilityName(widget.facilityId)}',
      icon: Icons.person_search_outlined,
      width: 760,
      scrollable: false,
      actions: [
        if (widget.allowUnassign && widget.currentOperatorId != null)
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(
              AssignmentChoice(
                operatorId: null,
                reason: emptyToNull(_reason.text),
              ),
            ),
            icon: const Icon(Icons.person_remove_outlined, size: 18),
            label: const Text('Rimuovi assegnazione'),
          ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _selected != null && changed
              ? () => Navigator.of(context).pop(
                  AssignmentChoice(
                    operatorId: _selected,
                    reason: emptyToNull(_reason.text),
                  ),
                )
              : null,
          child: Text(widget.confirmLabel),
        ),
      ],
      child: SizedBox(
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Filtra per nome, codice o qualifica',
                      prefixIcon: Icon(Icons.search, size: 19),
                    ),
                    onChanged: (value) => setState(() => _search = value),
                  ),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  label: const Text('Solo operatori della struttura'),
                  selected: _facilityOnly,
                  onSelected: (value) => setState(() => _facilityOnly = value),
                ),
              ],
            ),
            if (widget.requiredQualifications.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Qualifiche previste: ${widget.requiredQualifications.join(', ')}',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Expanded(
              child: _error != null
                  ? ErrorView(error: _error!, onRetry: _load)
                  : _candidates == null
                  ? const LoadingView(message: 'Verifica disponibilità…')
                  : candidates.isEmpty
                  ? const EmptyView(
                      title: 'Nessun operatore corrisponde ai filtri',
                      icon: Icons.person_off_outlined,
                    )
                  : ListView.separated(
                      itemCount: candidates.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final candidate = candidates[index];
                        return CandidateTile(
                          candidate: candidate,
                          selected: _selected == candidate.operator.id,
                          isCurrent:
                              widget.currentOperatorId == candidate.operator.id,
                          onTap: () =>
                              setState(() => _selected = candidate.operator.id),
                        );
                      },
                    ),
            ),
            if (widget.askReason) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                decoration: const InputDecoration(
                  labelText: 'Motivo (facoltativo, finisce nella cronologia)',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

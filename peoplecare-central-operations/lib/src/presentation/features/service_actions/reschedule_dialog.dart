import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/text.dart';
import '../../../domain/domain.dart';
import '../../app_scope.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/form_fields.dart';
import '../../shared/widgets/layout.dart';
import '../../theme/status_styles.dart';

/// Nuovo orario scelto nel dialogo di riprogrammazione.
class RescheduleChoice {
  const RescheduleChoice({required this.start, required this.end, this.reason});

  final DateTime start;
  final DateTime end;
  final String? reason;
}

/// Dialogo di riprogrammazione con verifica delle sovrapposizioni
/// dell'operatore assegnato.
Future<RescheduleChoice?> showRescheduleDialog(
  BuildContext context, {
  required Service service,
  DateTime? initialStart,
  DateTime? initialEnd,
  String title = 'Riprogramma servizio',
  bool askReason = true,
  String confirmLabel = 'Riprogramma',
}) {
  return showDialog<RescheduleChoice>(
    context: context,
    builder: (_) => _RescheduleDialog(
      service: service,
      initialStart: initialStart ?? service.scheduledStart,
      initialEnd: initialEnd ?? service.scheduledEnd,
      title: title,
      askReason: askReason,
      confirmLabel: confirmLabel,
    ),
  );
}

class _RescheduleDialog extends StatefulWidget {
  const _RescheduleDialog({
    required this.service,
    required this.initialStart,
    required this.initialEnd,
    required this.title,
    required this.askReason,
    required this.confirmLabel,
  });

  final Service service;
  final DateTime initialStart;
  final DateTime initialEnd;
  final String title;
  final bool askReason;
  final String confirmLabel;

  @override
  State<_RescheduleDialog> createState() => _RescheduleDialogState();
}

class _RescheduleDialogState extends State<_RescheduleDialog> {
  late DateTime _date = startOfDay(widget.initialStart);
  late int? _start = minutesSinceMidnight(widget.initialStart);
  late int? _end = _endMinutes(widget.initialStart, widget.initialEnd);
  final _reason = TextEditingController();
  List<Service> _overlaps = const [];
  bool _checking = false;
  Timer? _debounce;

  static int _endMinutes(DateTime start, DateTime end) =>
      end.difference(startOfDay(start)).inMinutes;

  @override
  void initState() {
    super.initState();
    _scheduleCheck();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _reason.dispose();
    super.dispose();
  }

  DateTime? get _startAt =>
      _start == null ? null : combineDateAndMinutes(_date, _start!);

  DateTime? get _endAt => _end == null
      ? null
      : combineDateAndMinutes(
          addDays(_date, _end! ~/ (24 * 60)),
          _end! % (24 * 60),
        );

  String? get _validation {
    final start = _startAt;
    final end = _endAt;
    if (start == null || end == null) return 'Indica inizio e fine.';
    return ServicePolicy.validateSchedule(start, end);
  }

  void _scheduleCheck() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _check);
  }

  Future<void> _check() async {
    final operatorId = widget.service.operatorId;
    final start = _startAt;
    final end = _endAt;
    if (operatorId == null ||
        start == null ||
        end == null ||
        _validation != null) {
      if (mounted) setState(() => _overlaps = const []);
      return;
    }
    setState(() => _checking = true);
    final deps = context.deps;
    try {
      final services = await deps.repositories.services.listServicesInRange(
        DateRange.day(start),
      );
      if (!mounted) return;
      setState(() {
        _overlaps = const ScheduleConflictDetector().overlapsForSlot(
          operatorId: operatorId,
          slot: DateRange(start, end),
          services: services,
          excludeServiceId: widget.service.id,
          now: deps.clock.now(),
        );
      });
    } on RepositoryException {
      // Verifica non disponibile: il sistema controllerà al salvataggio.
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _setStart(int? minutes) {
    setState(() {
      if (minutes != null && _start != null && _end != null) {
        // Sposta la fine mantenendo la durata.
        _end = minutes + (_end! - _start!);
      }
      _start = minutes;
    });
    _scheduleCheck();
  }

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final service = widget.service;
    final validation = _validation;
    final duration = validation == null ? _endAt!.difference(_startAt!) : null;
    return AppDialog(
      title: widget.title,
      subtitle:
          '${service.code} · ${service.kind.label} · ${service.patient.fullName}',
      icon: Icons.update,
      width: 600,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: validation == null
              ? () => Navigator.of(context).pop(
                  RescheduleChoice(
                    start: _startAt!,
                    end: _endAt!,
                    reason: emptyToNull(_reason.text),
                  ),
                )
              : null,
          child: Text(
            _overlaps.isEmpty ? widget.confirmLabel : 'Conferma comunque',
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow(
            label: 'Orario attuale',
            value: Fmt.slot(service.scheduledStart, service.scheduledEnd),
            icon: Icons.schedule,
          ),
          InfoRow(
            label: 'Operatore',
            value: deps.reference.operatorName(service.operatorId),
            icon: Icons.person_outline,
          ),
          const SizedBox(height: 14),
          DateField(
            label: 'Data',
            value: _date,
            onChanged: (value) {
              setState(() => _date = startOfDay(value));
              _scheduleCheck();
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TimeField(
                  label: 'Inizio',
                  value: _start,
                  onChanged: _setStart,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TimeField(
                  label: 'Fine',
                  value: _end == null ? null : _end! % (24 * 60),
                  onChanged: (minutes) {
                    setState(() {
                      if (minutes == null) {
                        _end = null;
                      } else {
                        // Fine prima dell'inizio: il giorno dopo (notturni).
                        _end = (_start != null && minutes <= _start!)
                            ? minutes + 24 * 60
                            : minutes;
                      }
                    });
                    _scheduleCheck();
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: Text(
                  duration == null ? '' : 'Durata\n${Fmt.duration(duration)}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          if (validation != null && _start != null && _end != null) ...[
            const SizedBox(height: 12),
            InlineBanner(
              style: severityStyle(context, NotificationSeverity.critica),
              message: validation,
            ),
          ],
          if (_overlaps.isNotEmpty) ...[
            const SizedBox(height: 12),
            InlineBanner(
              style: severityStyle(context, NotificationSeverity.attenzione),
              title: 'Sovrapposizione con altri servizi dell\'operatore',
              message: _overlaps
                  .map(
                    (s) =>
                        '${s.code} · ${Fmt.timeRange(s.scheduledStart, s.scheduledEnd)} · ${s.patient.fullName}',
                  )
                  .join('\n'),
            ),
          ] else if (_checking) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (widget.askReason) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(
                labelText: 'Motivo (facoltativo, finisce nella cronologia)',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

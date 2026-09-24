import 'package:flutter/material.dart';

import '../../../domain/domain.dart';
import '../../app_scope.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/layout.dart';
import '../../theme/status_styles.dart';
import '../documents/attachments.dart';
import '../service_form/service_form_dialog.dart';
import 'operator_picker.dart';
import 'reschedule_dialog.dart';

/// Azioni della Centrale su un servizio: dialoghi, chiamate ai repository e
/// messaggi di esito. Restituiscono il servizio aggiornato, o `null` se
/// l'utente annulla o l'operazione non riesce (errore già mostrato).
abstract final class ServiceActions {
  static const cancellationReasons = [
    'Richiesta della famiglia',
    'Paziente ricoverato',
    'Sospensione del piano assistenziale',
    'Inserito per errore',
  ];

  static const rescheduleReasons = [
    'Richiesta della famiglia',
    'Indisponibilità dell\'operatore',
    'Paziente non a domicilio',
    'Visita o esame concomitante',
  ];

  static Future<Service?> edit(BuildContext context, Service service) {
    return showServiceForm(context, existing: service);
  }

  static Future<Service?> duplicate(BuildContext context, Service service) {
    return showServiceForm(context, duplicateOf: service);
  }

  static Future<Service?> reschedule(
    BuildContext context,
    Service service,
  ) async {
    final choice = await showRescheduleDialog(context, service: service);
    if (choice == null || !context.mounted) return null;
    return runGuarded(
      context,
      () => context.deps.repositories.services.rescheduleService(
        service.id,
        start: choice.start,
        end: choice.end,
        reason: choice.reason,
        expectedVersion: service.version,
      ),
      success: 'Servizio riprogrammato: ${Fmt.slot(choice.start, choice.end)}',
    );
  }

  static Future<Service?> reassign(
    BuildContext context,
    Service service,
  ) async {
    final type = context.deps.reference.serviceType(service.serviceTypeId);
    final choice = await showAssignOperatorDialog(
      context,
      slot: service.scheduledRange,
      facilityId: service.facilityId,
      requiredQualifications: type?.requiredQualifications ?? const [],
      currentOperatorId: service.operatorId,
      excludeServiceId: service.id,
      title: service.operatorId == null
          ? 'Assegna operatore'
          : 'Riassegna servizio',
      subtitle:
          '${service.code} · ${service.kind.label} · '
          '${Fmt.slot(service.scheduledStart, service.scheduledEnd)}',
    );
    if (choice == null || !context.mounted) return null;
    final deps = context.deps;
    return runGuarded(
      context,
      () => deps.repositories.services.reassignService(
        service.id,
        operatorId: choice.operatorId,
        reason: choice.reason,
        expectedVersion: service.version,
      ),
      success: choice.operatorId == null
          ? 'Assegnazione rimossa: il servizio è da assegnare'
          : 'Servizio assegnato a ${deps.reference.operatorName(choice.operatorId)}',
    );
  }

  static Future<Service?> cancel(BuildContext context, Service service) async {
    final reason = await askText(
      context,
      title: 'Annulla servizio',
      message:
          '${service.code} · ${service.kind.label} per ${service.patient.fullName}, '
          '${Fmt.slot(service.scheduledStart, service.scheduledEnd)}.\n'
          'L\'operatore vedrà il servizio come annullato.',
      label: 'Motivo dell\'annullamento',
      confirmLabel: 'Annulla servizio',
      destructive: true,
      suggestions: cancellationReasons,
    );
    if (reason == null || !context.mounted) return null;
    return runGuarded(
      context,
      () => context.deps.repositories.services.cancelService(
        service.id,
        reason: reason,
        expectedVersion: service.version,
      ),
      success: 'Servizio annullato',
    );
  }

  static Future<Service?> markToReschedule(
    BuildContext context,
    Service service,
  ) async {
    final reason = await askText(
      context,
      title: 'Segna da riprogrammare',
      message: 'Il servizio resterà in evidenza finché non riceverà un nuovo orario.',
      label: 'Motivo',
      confirmLabel: 'Segna da riprogrammare',
      suggestions: rescheduleReasons,
    );
    if (reason == null || !context.mounted) return null;
    return runGuarded(
      context,
      () => context.deps.repositories.services.markToReschedule(
        service.id,
        reason: reason,
        expectedVersion: service.version,
      ),
      success: 'Servizio segnato da riprogrammare',
    );
  }

  /// `true` se il servizio è stato eliminato.
  static Future<bool> delete(BuildContext context, Service service) async {
    final blocked = ServicePolicy.deleteBlockedReason(service);
    if (blocked != null) {
      showMessage(context, blocked, error: true);
      return false;
    }
    final confirmed = await confirmAction(
      context,
      title: 'Eliminare il servizio?',
      message:
          '${service.code} · ${service.kind.label} per ${service.patient.fullName}.\n'
          'L\'eliminazione è definitiva e resta traccia solo nel registro attività.',
      confirmLabel: 'Elimina',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return false;
    final result = await runGuarded(context, () async {
      await context.deps.repositories.services.deleteService(
        service.id,
        expectedVersion: service.version,
      );
      return true;
    }, success: 'Servizio eliminato');
    return result ?? false;
  }

  static Future<List<DocumentInfo>> addDocuments(
    BuildContext context,
    Service service,
  ) {
    return showUploadDocumentsDialog(
      context,
      owner: DocumentOwner(
        type: DocumentOwnerType.servizio,
        id: service.id,
        label: '${service.code} - ${service.patient.fullName}',
      ),
    );
  }

  /// Spostamento dal calendario (trascinamento): nuovo operatore e/o nuovo
  /// orario, con riepilogo e conferma.
  static Future<Service?> move(
    BuildContext context,
    Service service, {
    required String? operatorId,
    required DateTime start,
  }) async {
    final deps = context.deps;
    final end = start.add(service.scheduledDuration);
    final timeChanged = start != service.scheduledStart;
    final operatorChanged = operatorId != service.operatorId;
    if (!timeChanged && !operatorChanged) return null;

    if (timeChanged && !ServicePolicy.canReschedule(service) ||
        operatorChanged && !ServicePolicy.canReassign(service)) {
      showMessage(
        context,
        'Il servizio non può essere spostato nello stato attuale.',
        error: true,
      );
      return null;
    }

    var overlaps = const <Service>[];
    if (operatorId != null) {
      try {
        final dayServices = await deps.repositories.services
            .listServicesInRange(DateRange.day(start));
        overlaps = const ScheduleConflictDetector().overlapsForSlot(
          operatorId: operatorId,
          slot: DateRange(start, end),
          services: dayServices,
          excludeServiceId: service.id,
          now: deps.clock.now(),
        );
      } on RepositoryException {
        overlaps = const [];
      }
    }
    if (!context.mounted) return null;

    final operator = deps.reference.operator(operatorId);
    if (operator != null && !operator.isAssignable) {
      showMessage(
        context,
        '${operator.fullName} non è attivo e non può ricevere servizi.',
        error: true,
      );
      return null;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: 'Confermi lo spostamento?',
        subtitle:
            '${service.code} · ${service.kind.label} · ${service.patient.fullName}',
        icon: Icons.open_with,
        width: 560,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(overlaps.isEmpty ? 'Conferma' : 'Conferma comunque'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (timeChanged)
              InfoRow(
                label: 'Orario',
                icon: Icons.schedule,
                value:
                    '${Fmt.slot(service.scheduledStart, service.scheduledEnd)}  →  '
                    '${Fmt.slot(start, end)}',
              ),
            if (operatorChanged)
              InfoRow(
                label: 'Operatore',
                icon: Icons.person_outline,
                value:
                    '${deps.reference.operatorName(service.operatorId)}  →  '
                    '${deps.reference.operatorName(operatorId)}',
              ),
            if (operator != null &&
                !operator.belongsTo(service.facilityId)) ...[
              const SizedBox(height: 10),
              InlineBanner(
                style: severityStyle(context, NotificationSeverity.attenzione),
                message:
                    '${operator.fullName} non appartiene a '
                    '${deps.reference.facilityName(service.facilityId)}.',
              ),
            ],
            if (overlaps.isNotEmpty) ...[
              const SizedBox(height: 10),
              InlineBanner(
                style: severityStyle(context, NotificationSeverity.attenzione),
                title: 'Sovrapposizione',
                message: overlaps
                    .map(
                      (s) =>
                          '${s.code} · ${Fmt.timeRange(s.scheduledStart, s.scheduledEnd)} · ${s.patient.fullName}',
                    )
                    .join('\n'),
              ),
            ],
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return null;

    return runGuarded(context, () async {
      var current = service;
      if (operatorChanged) {
        current = await deps.repositories.services.reassignService(
          current.id,
          operatorId: operatorId,
          reason: 'Spostato dal calendario',
          expectedVersion: current.version,
        );
      }
      if (timeChanged) {
        current = await deps.repositories.services.rescheduleService(
          current.id,
          start: start,
          end: end,
          reason: 'Spostato dal calendario',
          expectedVersion: current.version,
        );
      }
      return current;
    }, success: 'Servizio aggiornato');
  }
}

import 'package:flutter/material.dart';

import '../../../domain/domain.dart';
import '../../app_scope.dart';
import '../../shared/formatters.dart';
import '../../shared/labels.dart';
import '../../theme/app_palette.dart';
import '../../theme/status_styles.dart';

/// Testo del tooltip di un servizio nel calendario.
String serviceTooltip(
  BuildContext context,
  Service service, {
  bool conflict = false,
}) {
  final reference = context.deps.reference;
  final lines = [
    '${service.code} · ${service.status.label}',
    '${service.kind.label} · ${service.patient.fullName}',
    'Programmato ${Fmt.timeRange(service.scheduledStart, service.scheduledEnd)}',
    if (service.actualStart != null)
      'Effettivo ${Fmt.time(service.actualStart!)}'
          '${service.actualEnd == null ? ' (in corso)' : '–${Fmt.time(service.actualEnd!)}'}',
    'Operatore: ${reference.operatorName(service.operatorId)}',
    reference.facilityName(service.facilityId),
    service.address,
    if (service.priority == ServicePriority.urgente ||
        service.priority == ServicePriority.alta)
      'Priorità ${service.priority.label.toLowerCase()}',
    if (conflict) '⚠ Sovrapposto a un altro servizio dell\'operatore',
    if (service.openChangeRequestCount > 0) '✉ Richiesta di modifica aperta',
  ];
  return lines.join('\n');
}

/// Blocco di un servizio nella vista giorno.
class ServiceBlock extends StatelessWidget {
  const ServiceBlock({
    super.key,
    required this.service,
    required this.conflict,
    required this.onTap,
    this.dimmed = false,
    this.actualStartFraction,
    this.actualEndFraction,
  });

  final Service service;
  final bool conflict;
  final VoidCallback onTap;

  /// Servizio di un'altra struttura (con filtro struttura attivo).
  final bool dimmed;

  /// Posizione relativa (0-1) dell'intervallo reale dentro il blocco.
  final double? actualStartFraction;
  final double? actualEndFraction;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = serviceStatusStyle(context, service.status);
    final cancelled = service.status == ServiceStatus.annullato;
    final urgent = service.priority == ServicePriority.urgente;
    return Tooltip(
      message: serviceTooltip(context, service, conflict: conflict),
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Opacity(
            opacity: dimmed ? 0.5 : 1,
            child: Container(
              decoration: BoxDecoration(
                color: style.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: conflict ? palette.danger : style.border,
                  width: conflict ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 3,
                      child: ColoredBox(color: style.foreground),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 3, 1, 3),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 64;
                          // Interlinea fissa: due righe (27,6 px) entrano nel
                          // blocco anche con il bordo spesso dei conflitti.
                          final twoLines =
                              !narrow &&
                              constraints.maxHeight >= 2 * 11.5 * _lineHeight;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  if (!narrow && (conflict || urgent))
                                    Padding(
                                      padding: const EdgeInsets.only(right: 3),
                                      child: Icon(
                                        conflict
                                            ? Icons.warning_amber_rounded
                                            : Icons.priority_high,
                                        size: 13,
                                        color: palette.danger,
                                      ),
                                    ),
                                  Flexible(
                                    child: Text(
                                      narrow
                                          ? Fmt.time(service.scheduledStart)
                                          : Fmt.timeRange(
                                              service.scheduledStart,
                                              service.scheduledEnd,
                                            ),
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                      softWrap: false,
                                      style: TextStyle(
                                        fontSize: narrow ? 11 : 11.5,
                                        height: _lineHeight,
                                        fontWeight: FontWeight.w700,
                                        color: style.foreground,
                                        letterSpacing: narrow ? -0.2 : 0,
                                        decoration: cancelled
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                  ),
                                  if (!narrow &&
                                      service.openChangeRequestCount > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 3),
                                      child: Icon(
                                        Icons.mark_chat_unread_outlined,
                                        size: 12,
                                        color: palette.accent,
                                      ),
                                    ),
                                ],
                              ),
                              if (twoLines)
                                Text(
                                  '${service.patient.lastName} · ${service.kind.label}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    height: _lineHeight,
                                    color: palette.textPrimary,
                                    decoration: cancelled
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    if (actualStartFraction != null)
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final start = actualStartFraction!.clamp(0.0, 1.0);
                            final end = (actualEndFraction ?? 1.0).clamp(
                              start,
                              1.0,
                            );
                            return Stack(
                              children: [
                                Positioned(
                                  left: constraints.maxWidth * start,
                                  width: (constraints.maxWidth * (end - start))
                                      .clamp(2.0, constraints.maxWidth),
                                  bottom: 0,
                                  height: 3,
                                  child: ColoredBox(
                                    color: style.foreground.withValues(
                                      alpha: 0.75,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Etichetta compatta di un servizio nella vista settimana.
class ServiceChip extends StatelessWidget {
  const ServiceChip({
    super.key,
    required this.service,
    required this.conflict,
    required this.onTap,
    this.dimmed = false,
  });

  final Service service;
  final bool conflict;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = serviceStatusStyle(context, service.status);
    final cancelled = service.status == ServiceStatus.annullato;
    return Tooltip(
      message: serviceTooltip(context, service, conflict: conflict),
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Opacity(
            opacity: dimmed ? 0.5 : 1,
            child: Container(
              height: 22,
              margin: const EdgeInsets.only(bottom: 3),
              padding: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: style.background,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: conflict ? palette.danger : style.border,
                  width: conflict ? 1.6 : 0.8,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: style.foreground,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    Fmt.time(service.scheduledStart),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: style.foreground,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      service.patient.lastName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 11,
                        color: palette.textPrimary,
                        decoration: cancelled
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  if (conflict)
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 12,
                      color: palette.danger,
                    )
                  else if (service.priority == ServicePriority.urgente)
                    Icon(Icons.priority_high, size: 12, color: palette.danger),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Anteprima mostrata durante il trascinamento.
class DragPreview extends StatelessWidget {
  const DragPreview({super.key, required this.service, required this.width});

  final Service service;
  final double width;

  @override
  Widget build(BuildContext context) {
    final style = serviceStatusStyle(context, service.status);
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(6),
      color: style.background,
      child: Container(
        width: width,
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: style.foreground, width: 1.5),
        ),
        child: Text(
          '${Fmt.time(service.scheduledStart)} · ${service.patient.lastName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: style.foreground,
          ),
        ),
      ),
    );
  }
}

const _lineHeight = 1.2;

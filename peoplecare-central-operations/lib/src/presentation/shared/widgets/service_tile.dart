import 'package:flutter/material.dart';

import '../../../domain/domain.dart';
import '../../app_scope.dart';
import '../../theme/app_palette.dart';
import '../../theme/status_styles.dart';
import '../formatters.dart';
import 'badges.dart';

/// Riga compatta di un servizio negli elenchi (dashboard, pannelli).
class ServiceTile extends StatelessWidget {
  const ServiceTile({
    super.key,
    required this.service,
    this.onTap,
    this.trailing,
    this.showDate = false,
    this.subtitle,
  });

  final Service service;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showDate;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final reference = context.deps.reference;
    final style = serviceStatusStyle(context, service.status);
    final operator = reference.operator(service.operatorId);
    return InkWell(
      onTap: onTap,
      hoverColor: palette.hover,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 38,
              decoration: BoxDecoration(
                color: style.foreground,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: showDate ? 92 : 50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showDate)
                    Text(
                      Fmt.dayLabel(
                        service.scheduledStart,
                        context.deps.clock.now(),
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Text(
                    Fmt.time(service.scheduledStart),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (!showDate)
                    Text(
                      Fmt.time(service.scheduledEnd),
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.textMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${service.kind.label} · ${service.patient.fullName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (service.priority == ServicePriority.urgente ||
                          service.priority == ServicePriority.alta) ...[
                        const SizedBox(width: 6),
                        Icon(
                          priorityStyle(context, service.priority).icon,
                          size: 16,
                          color: priorityStyle(
                            context,
                            service.priority,
                          ).foreground,
                        ),
                      ],
                    ],
                  ),
                  Text(
                    subtitle ??
                        [
                          service.code,
                          operator?.fullName ?? 'Da assegnare',
                          reference.facilityName(service.facilityId),
                        ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ?? ServiceStatusBadge(service.status, dense: true),
          ],
        ),
      ),
    );
  }
}

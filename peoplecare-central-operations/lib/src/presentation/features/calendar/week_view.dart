import 'dart:math';

import 'package:flutter/material.dart';

import '../../../domain/domain.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/layout.dart';
import '../../theme/app_palette.dart';
import 'calendar_controller.dart';
import 'day_view.dart';
import 'service_block.dart';

/// Vista settimana: operatori per riga, giorni per colonna, servizi come
/// etichette compatte. "Da assegnare" resta fissa in alto.
class WeekView extends StatelessWidget {
  const WeekView({
    super.key,
    required this.controller,
    required this.callbacks,
    required this.onOpenDay,
  });

  final CalendarController controller;
  final CalendarCallbacks callbacks;
  final ValueChanged<DateTime> onOpenDay;

  static const leftWidth = 230.0;
  static const maxChips = 7;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final days = controller.range.days;
    final rows = controller.rows;
    final unassigned = controller.unassigned;
    return Column(
      children: [
        _DaysHeader(days: days, controller: controller, onOpenDay: onOpenDay),
        _WeekRow(
          days: days,
          controller: controller,
          callbacks: callbacks,
          onOpenDay: onOpenDay,
          operatorId: null,
          services: unassigned,
          background: palette.warningSoft.withValues(alpha: 0.55),
          header: _WeekRowHeader(
            title: 'Da assegnare',
            subtitle: Fmt.count(unassigned.length, 'servizio', 'servizi'),
            icon: Icons.person_search_outlined,
            color: palette.warning,
          ),
        ),
        Container(height: 2, color: palette.borderStrong),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return _WeekRow(
                key: ValueKey(row.operator.id),
                days: days,
                controller: controller,
                callbacks: callbacks,
                onOpenDay: onOpenDay,
                operatorId: row.operator.id,
                services: row.services,
                background: index.isOdd ? palette.surfaceMuted : null,
                header: _WeekRowHeader(
                  title: row.operator.fullName,
                  subtitle:
                      '${row.operator.qualification}\n'
                      '${Fmt.count(row.activeCount, 'servizio', 'servizi')} · '
                      '${Fmt.duration(row.plannedDuration)}',
                  avatar: InitialsAvatar(
                    initials: row.operator.initials,
                    colorKey: row.operator.id,
                    size: 30,
                    muted: !row.operator.isAssignable,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DaysHeader extends StatelessWidget {
  const _DaysHeader({
    required this.days,
    required this.controller,
    required this.onOpenDay,
  });

  final List<DateTime> days;
  final CalendarController controller;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: WeekView.leftWidth,
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                'OPERATORI (${controller.rows.length})',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: palette.textMuted,
                ),
              ),
            ),
          ),
          for (final day in days)
            Expanded(
              child: InkWell(
                onTap: () => onOpenDay(day),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: palette.border)),
                    color: isSameDay(day, controller.now)
                        ? primary.withValues(alpha: 0.08)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        Fmt.capitalize(Fmt.dayHeader(day)),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: isSameDay(day, controller.now)
                              ? primary
                              : palette.textPrimary,
                        ),
                      ),
                      Text(
                        _daySummary(day),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _daySummary(DateTime day) {
    final services = controller.services.where(
      (s) =>
          isSameDay(s.scheduledStart, day) &&
          s.status != ServiceStatus.annullato &&
          (controller.facilityId == null ||
              s.facilityId == controller.facilityId),
    );
    final total = services.length;
    final unassigned = services.where((s) => s.operatorId == null).length;
    return unassigned == 0
        ? Fmt.count(total, 'servizio', 'servizi')
        : '${Fmt.count(total, 'servizio', 'servizi')} · $unassigned da assegn.';
  }
}

class _WeekRowHeader extends StatelessWidget {
  const _WeekRowHeader({
    required this.title,
    required this.subtitle,
    this.avatar,
    this.icon,
    this.color,
  });

  final String title;
  final String subtitle;
  final Widget? avatar;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          avatar ?? Icon(icon, size: 24, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    color: color ?? palette.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({
    super.key,
    required this.days,
    required this.controller,
    required this.callbacks,
    required this.onOpenDay,
    required this.operatorId,
    required this.services,
    required this.header,
    this.background,
  });

  final List<DateTime> days;
  final CalendarController controller;
  final CalendarCallbacks callbacks;
  final ValueChanged<DateTime> onOpenDay;
  final String? operatorId;
  final List<Service> services;
  final Widget header;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final byDay = [
      for (final day in days)
        services.where((s) => isSameDay(s.scheduledStart, day)).toList()
          ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart)),
    ];
    final maxCount = byDay.fold<int>(0, (m, list) => max(m, list.length));
    final visible = min(maxCount, WeekView.maxChips);
    final overflow = maxCount > WeekView.maxChips ? 18.0 : 0.0;
    final height = max(58.0, visible * 25.0 + 12 + overflow);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: background,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: WeekView.leftWidth, child: header),
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: _DayCell(
                day: days[i],
                services: byDay[i],
                controller: controller,
                callbacks: callbacks,
                onOpenDay: onOpenDay,
                operatorId: operatorId,
              ),
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.services,
    required this.controller,
    required this.callbacks,
    required this.onOpenDay,
    required this.operatorId,
  });

  final DateTime day;
  final List<Service> services;
  final CalendarController controller;
  final CalendarCallbacks callbacks;
  final ValueChanged<DateTime> onOpenDay;
  final String? operatorId;

  bool _canMove(Service service) =>
      ServicePolicy.canReschedule(service) &&
      ServicePolicy.canReassign(service);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final weekend =
        day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
    final today = isSameDay(day, controller.now);
    final facilityFilter = controller.facilityId;
    final shown = services.take(WeekView.maxChips).toList();
    final hidden = services.length - shown.length;
    return DragTarget<Service>(
      onWillAcceptWithDetails: (details) => _canMove(details.data),
      onAcceptWithDetails: (details) {
        final service = details.data;
        final start = atTime(
          day,
          service.scheduledStart.hour,
          service.scheduledStart.minute,
        );
        callbacks.onMove(service, operatorId, start);
      },
      builder: (context, candidates, rejected) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTap: () => callbacks.onCreate(operatorId, atTime(day, 9, 0)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 5, 4, 2),
          decoration: BoxDecoration(
            color: candidates.isNotEmpty
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                : today
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.04)
                : weekend
                ? palette.weekendTint
                : null,
            border: Border(left: BorderSide(color: palette.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final service in shown)
                _chip(context, service, facilityFilter),
              if (hidden > 0)
                InkWell(
                  onTap: () => onOpenDay(day),
                  child: Text(
                    '+ altri $hidden',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, Service service, String? facilityFilter) {
    final chip = GestureDetector(
      onSecondaryTapUp: (details) =>
          callbacks.onContextMenu(service, details.globalPosition),
      child: ServiceChip(
        service: service,
        conflict: controller.hasConflict(service),
        dimmed: facilityFilter != null && service.facilityId != facilityFilter,
        onTap: () => callbacks.onOpen(service),
      ),
    );
    if (!_canMove(service)) return chip;
    return Draggable<Service>(
      data: service,
      maxSimultaneousDrags: 1,
      feedback: DragPreview(service: service, width: 150),
      childWhenDragging: Opacity(opacity: 0.3, child: chip),
      child: chip,
    );
  }
}

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../domain/domain.dart';
import '../../app_scope.dart';
import '../../shared/formatters.dart';
import '../../shared/labels.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/layout.dart';
import '../../theme/app_palette.dart';
import 'calendar_controller.dart';
import 'calendar_layout.dart';
import 'service_block.dart';

/// Callback del calendario.
class CalendarCallbacks {
  const CalendarCallbacks({
    required this.onOpen,
    required this.onMove,
    required this.onCreate,
    required this.onContextMenu,
  });

  final void Function(Service service) onOpen;
  final void Function(Service service, String? operatorId, DateTime start)
  onMove;
  final void Function(String? operatorId, DateTime start) onCreate;

  /// Menu contestuale di un servizio (clic destro).
  final void Function(Service service, Offset globalPosition) onContextMenu;
}

/// Geometria della fascia oraria visibile.
class _Geometry {
  _Geometry({
    required this.day,
    required this.fromHour,
    required this.toHour,
    required this.width,
  });

  final DateTime day;
  final int fromHour;
  final int toHour;
  final double width;

  int get hours => toHour - fromHour;

  double get hourWidth => width / hours;

  DateTime get start => atTime(day, fromHour, 0);

  DateTime get end =>
      toHour >= 24 ? addDays(startOfDay(day), 1) : atTime(day, toHour, 0);

  double xOf(DateTime time) {
    final minutes = time.difference(start).inMinutes;
    return (minutes / 60 * hourWidth).clamp(0.0, width);
  }

  DateTime timeAt(double x) {
    final minutes = snapMinutes(x / hourWidth * 60);
    return start.add(Duration(minutes: minutes));
  }
}

/// Vista giorno: una riga per operatore, servizi posizionati sull'asse orario,
/// corsie multiple quando si sovrappongono, riga "Da assegnare" fissa in alto.
class DayView extends StatelessWidget {
  const DayView({super.key, required this.controller, required this.callbacks});

  final CalendarController controller;
  final CalendarCallbacks callbacks;

  static const leftWidth = 250.0;
  static const laneHeight = 44.0;
  static const minBlockWidth = 40.0;
  static const rowPadding = 7.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final rows = controller.rows;
    final unassigned = controller.unassigned;
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = _Geometry(
          day: controller.anchor,
          fromHour: controller.hourWindow.from,
          toHour: controller.hourWindow.to,
          width: max(200, constraints.maxWidth - leftWidth - 12),
        );
        return Column(
          children: [
            _Ruler(geometry: geometry, controller: controller),
            _TimelineRow(
              key: const ValueKey('unassigned'),
              geometry: geometry,
              controller: controller,
              callbacks: callbacks,
              operatorId: null,
              services: unassigned,
              background: palette.warningSoft.withValues(alpha: 0.55),
              header: _UnassignedHeader(count: unassigned.length),
            ),
            Container(height: 2, color: palette.borderStrong),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Text(
                        'Nessun operatore corrisponde ai filtri.',
                        style: TextStyle(color: palette.textMuted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        return _TimelineRow(
                          key: ValueKey(row.operator.id),
                          geometry: geometry,
                          controller: controller,
                          callbacks: callbacks,
                          operatorId: row.operator.id,
                          services: row.services,
                          background: index.isOdd ? palette.surfaceMuted : null,
                          header: _OperatorHeader(
                            row: row,
                            controller: controller,
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

class _Ruler extends StatelessWidget {
  const _Ruler({required this.geometry, required this.controller});

  final _Geometry geometry;
  final CalendarController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final now = controller.now;
    final showNow =
        isSameDay(now, controller.anchor) &&
        now.isAfter(geometry.start) &&
        now.isBefore(geometry.end);
    final step = geometry.hourWidth < 48 ? 2 : 1;
    final nowX = showNow ? geometry.xOf(now) : null;
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: DayView.leftWidth,
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
          SizedBox(
            width: geometry.width,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var h = 0; h <= geometry.hours; h += step)
                  // Le etichette coperte dal badge dell'ora attuale sono omesse.
                  if (nowX == null ||
                      (h * geometry.hourWidth - nowX).abs() >= 40)
                    Positioned(
                      left: h * geometry.hourWidth - 20,
                      width: 40,
                      top: 9,
                      child: Text(
                        Fmt.minutesOfDay((geometry.fromHour + h) * 60),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: palette.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                if (showNow)
                  Positioned(
                    left: nowX! - 22,
                    top: 6,
                    child: Container(
                      width: 44,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: palette.nowLine,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        Fmt.time(now),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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

class _UnassignedHeader extends StatelessWidget {
  const _UnassignedHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: palette.warning.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_search_outlined,
              size: 19,
              color: palette.warning,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Da assegnare',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: palette.warning,
                  ),
                ),
                Text(
                  switch (count) {
                    0 => 'Tutti i servizi assegnati',
                    1 => '1 servizio senza operatore',
                    _ => '$count servizi senza operatore',
                  },
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OperatorHeader extends StatelessWidget {
  const _OperatorHeader({required this.row, required this.controller});

  final CalendarRow row;
  final CalendarController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final operator = row.operator;
    final reference = context.deps.reference;
    final today = isSameDay(controller.now, controller.anchor);
    final onDuty = today && controller.isOnDuty(operator.id);
    final dotColor = !operator.isAssignable
        ? palette.warning
        : (onDuty ? palette.success : palette.textMuted.withValues(alpha: 0.5));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              InitialsAvatar(
                initials: operator.initials,
                colorKey: operator.id,
                muted: !operator.isAssignable,
              ),
              Positioned(
                right: -1,
                bottom: -1,
                child: Tooltip(
                  message: !operator.isAssignable
                      ? 'Operatore ${operator.status.label.toLowerCase()}'
                      : (onDuty
                            ? 'In servizio ora'
                            : 'Nessun servizio in corso'),
                  child: StatusDot(
                    color: dotColor,
                    size: 11,
                    ring: palette.surface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  operator.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                Text(
                  !operator.isAssignable
                      ? 'Operatore ${operator.status.label.toLowerCase()}'
                      : '${operator.qualification} · '
                            '${reference.facility(operator.primaryFacilityId)?.code ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: operator.isAssignable
                        ? palette.textSecondary
                        : palette.warning,
                  ),
                ),
                Text(
                  '${Fmt.count(row.activeCount, 'servizio', 'servizi')} · '
                  '${Fmt.duration(row.plannedDuration)}',
                  maxLines: 1,
                  style: TextStyle(fontSize: 11.5, color: palette.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatefulWidget {
  const _TimelineRow({
    super.key,
    required this.geometry,
    required this.controller,
    required this.callbacks,
    required this.operatorId,
    required this.services,
    required this.header,
    this.background,
  });

  final _Geometry geometry;
  final CalendarController controller;
  final CalendarCallbacks callbacks;
  final String? operatorId;
  final List<Service> services;
  final Widget header;
  final Color? background;

  @override
  State<_TimelineRow> createState() => _TimelineRowState();
}

class _TimelineRowState extends State<_TimelineRow> {
  final _areaKey = GlobalKey();

  bool _canMove(Service service) =>
      ServicePolicy.canReschedule(service) &&
      ServicePolicy.canReassign(service);

  Offset _toLocal(Offset global) {
    final box = _areaKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global) ?? Offset.zero;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final geometry = widget.geometry;
    final controller = widget.controller;
    final visible = widget.services
        .where(
          (s) =>
              s.scheduledEnd.isAfter(geometry.start) &&
              s.scheduledStart.isBefore(geometry.end),
        )
        .toList();
    // Larghezza minima leggibile: le corsie tengono conto dell'ingombro
    // visivo, così i blocchi brevi non si coprono tra loro.
    final minVisual = Duration(
      minutes: (DayView.minBlockWidth / geometry.hourWidth * 60).ceil(),
    );
    DateTime visualEnd(Service s) {
      final minEnd = s.scheduledStart.add(minVisual);
      return s.scheduledEnd.isAfter(minEnd) ? s.scheduledEnd : minEnd;
    }

    final layout = assignLanes<Service>(
      visible,
      start: (s) => s.scheduledStart,
      end: visualEnd,
    );
    final height = max(
      62.0,
      layout.laneCount * DayView.laneHeight + DayView.rowPadding * 2,
    );
    final now = controller.now;
    final showNow =
        isSameDay(now, controller.anchor) &&
        now.isAfter(geometry.start) &&
        now.isBefore(geometry.end);
    final facilityFilter = controller.facilityId;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: widget.background,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          SizedBox(width: DayView.leftWidth, child: widget.header),
          SizedBox(
            width: geometry.width,
            child: DragTarget<Service>(
              onWillAcceptWithDetails: (details) => _canMove(details.data),
              onAcceptWithDetails: (details) {
                final local = _toLocal(details.offset);
                final start = geometry.timeAt(max(0, local.dx));
                widget.callbacks.onMove(details.data, widget.operatorId, start);
              },
              builder: (context, candidates, rejected) {
                final hovering = candidates.isNotEmpty;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onSecondaryTapUp: (details) {
                    final start = geometry.timeAt(details.localPosition.dx);
                    widget.callbacks.onCreate(widget.operatorId, start);
                  },
                  child: Stack(
                    key: _areaKey,
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _GridPainter(
                            geometry: geometry,
                            line: palette.gridLine,
                            strongLine: palette.gridLineStrong,
                            pastTint: showNow
                                ? palette.textMuted.withValues(alpha: 0.05)
                                : null,
                            nowX: showNow ? geometry.xOf(now) : null,
                            highlight: hovering
                                ? Theme.of(context).colorScheme.primary
                                      .withValues(alpha: 0.08)
                                : null,
                          ),
                        ),
                      ),
                      for (final placement in layout.placements)
                        _positioned(context, placement, facilityFilter),
                      if (showNow)
                        Positioned(
                          left: geometry.xOf(now) - 1,
                          top: 0,
                          bottom: 0,
                          width: 2,
                          child: IgnorePointer(
                            child: ColoredBox(color: palette.nowLine),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _positioned(
    BuildContext context,
    LanePlacement<Service> placement,
    String? facilityFilter,
  ) {
    final geometry = widget.geometry;
    final service = placement.item;
    final left = geometry.xOf(service.scheduledStart);
    final right = geometry.xOf(service.scheduledEnd);
    final width = max(right - left, DayView.minBlockWidth);
    final conflict = widget.controller.hasConflict(service);
    final scheduledMinutes = service.scheduledDuration.inMinutes;
    double? actualStart;
    double? actualEnd;
    if (service.actualStart != null && scheduledMinutes > 0) {
      actualStart =
          service.actualStart!.difference(service.scheduledStart).inMinutes /
          scheduledMinutes;
      final end =
          service.actualEnd ??
          (service.status == ServiceStatus.inCorso
              ? widget.controller.now
              : null);
      actualEnd = end == null
          ? null
          : end.difference(service.scheduledStart).inMinutes / scheduledMinutes;
    }
    final block = ServiceBlock(
      service: service,
      conflict: conflict,
      dimmed: facilityFilter != null && service.facilityId != facilityFilter,
      actualStartFraction: actualStart,
      actualEndFraction: actualEnd,
      onTap: () => widget.callbacks.onOpen(service),
    );
    final interactive = GestureDetector(
      onSecondaryTapUp: (details) =>
          widget.callbacks.onContextMenu(service, details.globalPosition),
      child: block,
    );
    return Positioned(
      left: left,
      width: width,
      top: DayView.rowPadding + placement.lane * DayView.laneHeight,
      height: DayView.laneHeight - 5,
      child: _canMove(service)
          ? Draggable<Service>(
              data: service,
              maxSimultaneousDrags: 1,
              feedback: DragPreview(service: service, width: max(width, 90)),
              childWhenDragging: Opacity(opacity: 0.3, child: block),
              child: interactive,
            )
          : interactive,
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.geometry,
    required this.line,
    required this.strongLine,
    this.pastTint,
    this.nowX,
    this.highlight,
  });

  final _Geometry geometry;
  final Color line;
  final Color strongLine;
  final Color? pastTint;
  final double? nowX;
  final Color? highlight;

  @override
  void paint(Canvas canvas, Size size) {
    if (highlight != null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = highlight!);
    }
    if (pastTint != null && nowX != null) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, nowX!, size.height),
        Paint()..color = pastTint!,
      );
    }
    final strong = Paint()
      ..color = strongLine
      ..strokeWidth = 1;
    final light = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var h = 0; h <= geometry.hours; h++) {
      final x = h * geometry.hourWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), strong);
      if (h < geometry.hours && geometry.hourWidth >= 40) {
        final half = x + geometry.hourWidth / 2;
        canvas.drawLine(Offset(half, 0), Offset(half, size.height), light);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      oldDelegate.geometry.width != geometry.width ||
      oldDelegate.geometry.fromHour != geometry.fromHour ||
      oldDelegate.geometry.toHour != geometry.toHour ||
      oldDelegate.nowX != nowX ||
      oldDelegate.highlight != highlight ||
      oldDelegate.line != line;
}

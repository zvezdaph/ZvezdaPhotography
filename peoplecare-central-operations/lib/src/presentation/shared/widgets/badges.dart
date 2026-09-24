import 'package:flutter/material.dart';

import '../../../domain/domain.dart';
import '../../theme/app_palette.dart';
import '../../theme/status_styles.dart';
import '../labels.dart';

/// Etichetta a pillola con icona, testo e colori di stato.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.style,
    this.dense = false,
    this.showIcon = true,
    this.tooltip,
  });

  final String label;
  final StatusStyle style;
  final bool dense;
  final bool showIcon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: style.border, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(style.icon, size: dense ? 12 : 14, color: style.foreground),
            SizedBox(width: dense ? 3 : 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: style.foreground,
                fontSize: dense ? 11.5 : 12.5,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip, child: pill);
  }
}

class ServiceStatusBadge extends StatelessWidget {
  const ServiceStatusBadge(this.status, {super.key, this.dense = false});

  final ServiceStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) => Pill(
    label: status.label,
    style: serviceStatusStyle(context, status),
    dense: dense,
  );
}

class PriorityBadge extends StatelessWidget {
  const PriorityBadge(
    this.priority, {
    super.key,
    this.dense = false,
    this.hideNormal = false,
  });

  final ServicePriority priority;
  final bool dense;

  /// Non mostra nulla per la priorità normale (tabelle dense).
  final bool hideNormal;

  @override
  Widget build(BuildContext context) {
    if (hideNormal && priority == ServicePriority.normale) {
      return const SizedBox.shrink();
    }
    return Pill(
      label: priority.label,
      style: priorityStyle(context, priority),
      dense: dense,
    );
  }
}

class OperatorStatusBadge extends StatelessWidget {
  const OperatorStatusBadge(this.status, {super.key, this.dense = false});

  final OperatorStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) => Pill(
    label: status.label,
    style: operatorStatusStyle(context, status),
    dense: dense,
  );
}

class ChangeRequestStatusBadge extends StatelessWidget {
  const ChangeRequestStatusBadge(this.status, {super.key, this.dense = false});

  final ChangeRequestStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) => Pill(
    label: status.label,
    style: changeRequestStatusStyle(context, status),
    dense: dense,
  );
}

/// Etichetta neutra (tag), es. qualifica o categoria.
class TagChip extends StatelessWidget {
  const TagChip(this.label, {super.key, this.color, this.icon});

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final base = color ?? palette.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: base.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: base),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: color ?? palette.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Contatore numerico (badge della barra laterale, schede).
class CountBadge extends StatelessWidget {
  const CountBadge(
    this.count, {
    super.key,
    this.color,
    this.textColor = Colors.white,
    this.max = 99,
  });

  final int count;
  final Color? color;
  final Color textColor;
  final int max;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final text = count > max ? '$max+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? context.palette.danger,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

/// Punto colorato di stato (es. operatore in servizio).
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 9, this.ring});

  final Color color;
  final double size;
  final Color? ring;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: ring == null ? null : Border.all(color: ring!, width: 2),
    ),
  );
}

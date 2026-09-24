import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';

/// Indicatore sintetico cliccabile.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.caption,
    this.color,
    this.onTap,
    this.emphasis = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? caption;
  final Color? color;
  final VoidCallback? onTap;

  /// Evidenzia il riquadro (valore che richiede attenzione).
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accent = color ?? Theme.of(context).colorScheme.primary;
    return Material(
      color: emphasis ? accent.withValues(alpha: 0.07) : palette.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        hoverColor: palette.hover,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: emphasis ? accent.withValues(alpha: 0.45) : palette.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                        color: emphasis ? accent : palette.textPrimary,
                      ),
                    ),
                    if (caption != null)
                      Tooltip(
                        message: caption!,
                        waitDuration: const Duration(milliseconds: 600),
                        child: Text(
                          caption!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, size: 18, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra di avanzamento segmentata (es. completati / in corso / da fare).
class SegmentedProgressBar extends StatelessWidget {
  const SegmentedProgressBar({
    super.key,
    required this.segments,
    this.height = 8,
  });

  /// Valore e colore di ogni segmento.
  final List<(num, Color)> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<num>(0, (sum, s) => sum + s.$1);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: total == 0
            ? ColoredBox(color: context.palette.border)
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (value, color) in segments)
                    if (value > 0)
                      Expanded(
                        flex: (value * 1000 / total).round().clamp(1, 1000),
                        child: ColoredBox(color: color),
                      ),
                ],
              ),
      ),
    );
  }
}

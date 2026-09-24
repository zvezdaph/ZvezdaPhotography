import 'package:flutter/material.dart';

import '../../app/status_model.dart';
import '../theme.dart';

/// Traffic light indicator: CAMERA / CLOUDFLARE / REGIA.
class StatusLight extends StatelessWidget {
  const StatusLight({super.key, required this.label, required this.light, this.detail});

  final String label;
  final Light light;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.light(light);
    return Tooltip(
      message: detail ?? label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [if (light != Light.off) BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        ]),
      ),
    );
  }
}

/// The big LIVE badge: red only when the stream is really connected.
class LiveBadgeView extends StatefulWidget {
  const LiveBadgeView({super.key, required this.badge, this.compact = false});

  final LiveBadge badge;
  final bool compact;

  @override
  State<LiveBadgeView> createState() => _LiveBadgeViewState();
}

class _LiveBadgeViewState extends State<LiveBadgeView> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badge = widget.badge;
    final color = switch (badge) {
      LiveBadge.live => AppColors.red,
      LiveBadge.paused || LiveBadge.reconnecting || LiveBadge.connecting => AppColors.amber,
      LiveBadge.error => const Color(0xFF8A1F28),
      LiveBadge.offline => const Color(0xFF2A323C),
    };
    final label = StatusModel.badgeLabel(badge);
    final child = Container(
      padding: EdgeInsets.symmetric(horizontal: widget.compact ? 10 : 18, vertical: widget.compact ? 4 : 8),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (badge == LiveBadge.live) ...[
          const Icon(Icons.circle, size: 12, color: Colors.white),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: TextStyle(
            color: badge == LiveBadge.paused || badge == LiveBadge.reconnecting || badge == LiveBadge.connecting
                ? Colors.black
                : Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            fontSize: widget.compact ? 13 : 20,
          ),
        ),
      ]),
    );
    if (badge != LiveBadge.live) return child;
    return FadeTransition(opacity: Tween(begin: 0.65, end: 1.0).animate(_pulse), child: child);
  }
}

class InfoChip extends StatelessWidget {
  const InfoChip({super.key, required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: color ?? AppColors.muted),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color ?? AppColors.text)),
      ]),
    );
  }
}

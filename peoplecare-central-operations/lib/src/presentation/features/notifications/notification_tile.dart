import 'package:flutter/material.dart';

import '../../../domain/domain.dart';
import '../../app_scope.dart';
import '../../shared/formatters.dart';
import '../../shared/labels.dart';
import '../../shared/widgets/badges.dart';
import '../../theme/app_palette.dart';
import '../../theme/status_styles.dart';
import 'notification_actions.dart';

/// Riga di notifica (pannello rapido e pagina Notifiche).
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    this.dense = false,
  });

  final AppNotification notification;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = severityStyle(context, notification.severity);
    final now = context.deps.clock.now();
    final unread = !notification.isRead;
    return Material(
      color: unread
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.04)
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          MenuController.maybeOf(context)?.close();
          openNotificationTarget(context, notification);
        },
        hoverColor: palette.hover,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: dense ? 10 : 14,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: dense ? 32 : 38,
                height: dense ? 32 : 38,
                decoration: BoxDecoration(
                  color: style.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  notificationIcon(notification.type),
                  size: dense ? 18 : 20,
                  color: style.foreground,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        Text(
                          Fmt.relative(notification.createdAt, now),
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      notification.message,
                      maxLines: dense ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    if (!dense) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Pill(
                            label: notification.type.label,
                            style: style,
                            dense: true,
                            showIcon: false,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (unread)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 6),
                  child: StatusDot(
                    color: Theme.of(context).colorScheme.primary,
                    size: 8,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/domain.dart';
import '../app_scope.dart';
import '../features/notifications/notification_actions.dart';
import '../theme/app_palette.dart';
import '../theme/status_styles.dart';

/// Avvisi a comparsa (in alto a destra) per le notifiche in tempo reale.
class ToastOverlay extends StatefulWidget {
  const ToastOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastEntry {
  _ToastEntry(this.notification, this.timer);

  final AppNotification notification;
  final Timer timer;
}

class _ToastOverlayState extends State<ToastOverlay> {
  final _toasts = <_ToastEntry>[];
  StreamSubscription<AppNotification>? _subscription;

  static const _maxVisible = 4;
  static const _lifetime = Duration(seconds: 7);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_subscription != null) return;
    final center = context.deps.notifications;
    _subscription = center.incoming.listen((notification) {
      if (!mounted || !center.shouldToast(notification)) return;
      setState(() {
        _toasts.insert(
          0,
          _ToastEntry(
            notification,
            Timer(_lifetime, () => _remove(notification.id)),
          ),
        );
        while (_toasts.length > _maxVisible) {
          _toasts.removeLast().timer.cancel();
        }
      });
    });
  }

  void _remove(String id) {
    if (!mounted) return;
    setState(() {
      _toasts.removeWhere((toast) {
        if (toast.notification.id != id) return false;
        toast.timer.cancel();
        return true;
      });
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    for (final toast in _toasts) {
      toast.timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 72,
          right: 20,
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final toast in _toasts)
                Padding(
                  key: ValueKey(toast.notification.id),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ToastCard(
                    notification: toast.notification,
                    onClose: () => _remove(toast.notification.id),
                    onOpen: () {
                      _remove(toast.notification.id);
                      openNotificationTarget(context, toast.notification);
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({
    required this.notification,
    required this.onClose,
    required this.onOpen,
  });

  final AppNotification notification;
  final VoidCallback onClose;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = severityStyle(context, notification.severity);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(24 * (1 - value), 0),
          child: child,
        ),
      ),
      child: Material(
        elevation: 8,
        shadowColor: Colors.black26,
        color: palette.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onOpen,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(color: style.foreground, width: 4),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  notificationIcon(notification.type),
                  color: style.foreground,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        notification.message,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Chiudi',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 17),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

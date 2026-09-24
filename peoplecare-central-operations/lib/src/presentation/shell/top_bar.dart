import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../app_state/navigation_controller.dart';
import '../features/notifications/notification_tile.dart';
import '../shared/formatters.dart';
import '../shared/widgets/badges.dart';
import '../shared/widgets/states.dart';
import '../theme/app_palette.dart';

/// Barra superiore: titolo della sezione, ricerca rapida, nuovo servizio,
/// notifiche, orologio e tema.
class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.onQuickSearch,
    required this.onNewService,
  });

  final VoidCallback onQuickSearch;
  final VoidCallback onNewService;

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          ListenableBuilder(
            listenable: deps.navigation,
            builder: (context, _) {
              final section = deps.navigation.current;
              return Row(
                children: [
                  Text(
                    section.group,
                    style: TextStyle(color: palette.textMuted, fontSize: 13.5),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: palette.textMuted,
                    ),
                  ),
                  Text(
                    section.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
            },
          ),
          const Spacer(),
          _QuickSearchButton(onPressed: onQuickSearch),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onNewService,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Nuovo servizio'),
          ),
          const SizedBox(width: 12),
          const _NotificationBell(),
          const SizedBox(width: 4),
          ListenableBuilder(
            listenable: deps.theme,
            builder: (context, _) => IconButton(
              tooltip: deps.theme.isDark ? 'Tema chiaro' : 'Tema scuro',
              onPressed: deps.theme.toggle,
              icon: Icon(
                deps.theme.isDark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const _Clock(),
        ],
      ),
    );
  }
}

class _QuickSearchButton extends StatelessWidget {
  const _QuickSearchButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: 'Ricerca rapida (Ctrl+K)',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 320,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: palette.surfaceMuted,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 19, color: palette.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cerca servizi, operatori, pazienti…',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.textMuted, fontSize: 13.5),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: palette.borderStrong),
                ),
                child: Text(
                  'Ctrl K',
                  style: TextStyle(
                    fontSize: 11,
                    color: palette.textSecondary,
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
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    return ListenableBuilder(
      listenable: deps.notifications,
      builder: (context, _) {
        final count = deps.notifications.unreadCount;
        return MenuAnchor(
          alignmentOffset: const Offset(-340, 6),
          style: const MenuStyle(
            padding: WidgetStatePropertyAll(EdgeInsets.zero),
          ),
          menuChildren: const [_NotificationsPopover()],
          builder: (context, controller, _) => Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: count == 0
                    ? 'Notifiche'
                    : 'Notifiche ($count non lette)',
                onPressed: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    unawaited(deps.notifications.refresh());
                    controller.open();
                  }
                },
                icon: Icon(
                  count > 0
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_none_outlined,
                ),
              ),
              if (count > 0)
                Positioned(
                  right: 2,
                  top: 2,
                  child: IgnorePointer(child: CountBadge(count)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _NotificationsPopover extends StatelessWidget {
  const _NotificationsPopover();

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    return ListenableBuilder(
      listenable: deps.notifications,
      builder: (context, _) {
        final items = deps.notifications.recent;
        return SizedBox(
          width: 400,
          height: 470,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Text(
                      'Notifiche',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: 8),
                    CountBadge(deps.notifications.unreadCount),
                    const Spacer(),
                    TextButton(
                      onPressed: deps.notifications.unreadCount == 0
                          ? null
                          : () => unawaited(deps.notifications.markAllRead()),
                      child: const Text('Segna tutte lette'),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: palette.border),
              Expanded(
                child: items.isEmpty
                    ? const EmptyView(
                        title: 'Nessuna notifica',
                        icon: Icons.notifications_off_outlined,
                        compact: true,
                      )
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: palette.border),
                        itemBuilder: (context, index) => NotificationTile(
                          notification: items[index],
                          dense: true,
                        ),
                      ),
              ),
              Divider(height: 1, color: palette.border),
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: SwitchListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        title: const Text(
                          'Avvisi per inizio/fine servizi',
                          style: TextStyle(fontSize: 12.5),
                        ),
                        value: deps.notifications.showRoutineToasts,
                        onChanged: deps.notifications.setShowRoutineToasts,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        MenuController.maybeOf(context)?.close();
                        deps.navigation.go(AppSection.notifications);
                      },
                      child: const Text('Vedi tutte'),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = context.deps.clock.now();
    final palette = context.palette;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          Fmt.time(now),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          Fmt.capitalize(Fmt.dayMedium(now)),
          style: TextStyle(fontSize: 11.5, color: palette.textSecondary),
        ),
      ],
    );
  }
}

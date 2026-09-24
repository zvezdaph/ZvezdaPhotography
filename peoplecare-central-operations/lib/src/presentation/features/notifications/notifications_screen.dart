import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/domain.dart';
import '../../app_scope.dart';
import '../../app_state/screen_controller.dart';
import '../../app_state/section_activity.dart';
import '../../shared/formatters.dart';
import '../../shared/labels.dart';
import '../../shared/widgets/filters.dart';
import '../../shared/widgets/layout.dart';
import '../../shared/widgets/states.dart';
import '../../theme/app_palette.dart';
import '../../theme/status_styles.dart';
import 'notification_tile.dart';

class NotificationsController extends ScreenController {
  NotificationsController({required PeopleCareRepositories repositories})
    : _repositories = repositories,
      super(
        events: repositories.events,
        topics: const {OperationalEventTopic.notifiche},
        refreshDebounce: const Duration(milliseconds: 250),
      );

  final PeopleCareRepositories _repositories;

  bool unreadOnly = false;
  Set<NotificationType> types = {};
  List<AppNotification> notifications = const [];

  @override
  Future<void> fetch() async {
    notifications = await _repositories.notifications.listNotifications(
      NotificationQuery(unreadOnly: unreadOnly, types: types, limit: 400),
    );
  }

  void setUnreadOnly(bool value) {
    unreadOnly = value;
    unawaited(load());
  }

  void setTypes(Set<NotificationType> value) {
    types = value;
    unawaited(load());
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final NotificationsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = NotificationsController(
      repositories: AppScope.of(context).repositories,
    );
    unawaited(_controller.load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.setActive(SectionActivity.of(context));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, deps.notifications]),
      builder: (context, _) {
        final now = deps.clock.now();
        final grouped = <String, List<AppNotification>>{};
        for (final notification in _controller.notifications) {
          grouped
              .putIfAbsent(Fmt.dayLabel(notification.createdAt, now), () => [])
              .add(notification);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Notifiche',
              subtitle:
                  'Eventi dal territorio e dal sistema: richieste di modifica, '
                  'inizio e fine servizi, documenti ricevuti, anomalie.',
              actions: [
                OutlinedButton.icon(
                  onPressed: deps.notifications.unreadCount == 0
                      ? null
                      : () => unawaited(deps.notifications.markAllRead()),
                  icon: const Icon(Icons.done_all, size: 18),
                  label: Text(
                    'Segna tutte come lette (${deps.notifications.unreadCount})',
                  ),
                ),
              ],
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilterBar(
                      trailing: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Avvisi a comparsa per inizio/fine servizi',
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                            Switch(
                              value: deps.notifications.showRoutineToasts,
                              onChanged:
                                  deps.notifications.setShowRoutineToasts,
                            ),
                          ],
                        ),
                      ],
                      children: [
                        SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: [
                            const ButtonSegment(
                              value: false,
                              label: Text('Tutte'),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text(
                                'Non lette (${deps.notifications.unreadCount})',
                              ),
                            ),
                          ],
                          selected: {_controller.unreadOnly},
                          onSelectionChanged: (value) =>
                              _controller.setUnreadOnly(value.first),
                        ),
                        MultiFilterMenu<NotificationType>(
                          label: 'Tipo',
                          icon: Icons.filter_list,
                          allLabel: 'Tutti',
                          values: _controller.types,
                          options: [
                            for (final type in NotificationType.values)
                              FilterOption(
                                type,
                                type.label,
                                icon: notificationIcon(type),
                              ),
                          ],
                          onChanged: _controller.setTypes,
                        ),
                      ],
                    ),
                    Divider(height: 1, color: palette.border),
                    RefreshingBar(
                      visible: _controller.isLoading && _controller.hasLoaded,
                    ),
                    Expanded(
                      child: !_controller.hasLoaded
                          ? (_controller.error != null
                                ? ErrorView(
                                    error: _controller.error!,
                                    onRetry: _controller.load,
                                  )
                                : const LoadingView())
                          : _controller.notifications.isEmpty
                          ? const EmptyView(
                              title: 'Nessuna notifica',
                              icon: Icons.notifications_off_outlined,
                            )
                          : ListView(
                              children: [
                                for (final MapEntry(key: day, value: items)
                                    in grouped.entries) ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      14,
                                      20,
                                      6,
                                    ),
                                    child: SectionLabel(
                                      '$day · ${items.length}',
                                      padding: EdgeInsets.zero,
                                    ),
                                  ),
                                  for (final notification in items) ...[
                                    NotificationTile(
                                      notification: notification,
                                    ),
                                    Divider(height: 1, color: palette.border),
                                  ],
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

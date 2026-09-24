import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/domain.dart';

/// Stato globale delle notifiche: contatore non lette, elenco recente per il
/// pannello rapido e flusso delle nuove notifiche per gli avvisi a comparsa.
class NotificationCenter extends ChangeNotifier {
  NotificationCenter({
    required NotificationRepository repository,
    required OperationalEventsRepository events,
  }) : _repository = repository {
    _eventSubscription = events.watchEvents().listen((event) {
      if (event.topic == OperationalEventTopic.notifiche) _scheduleRefresh();
    });
    _newSubscription = repository.watchNew().listen((notification) {
      if (!_incoming.isClosed) _incoming.add(notification);
    });
  }

  final NotificationRepository _repository;
  StreamSubscription<OperationalEvent>? _eventSubscription;
  StreamSubscription<AppNotification>? _newSubscription;
  final _incoming = StreamController<AppNotification>.broadcast();
  Timer? _debounce;
  bool _disposed = false;

  int _unreadCount = 0;
  List<AppNotification> _recent = const [];

  /// Avvisi a comparsa anche per inizio/fine servizio (di default solo per
  /// richieste, documenti e problemi).
  bool showRoutineToasts = false;

  int get unreadCount => _unreadCount;

  List<AppNotification> get recent => _recent;

  /// Nuove notifiche in arrivo (per gli avvisi a comparsa).
  Stream<AppNotification> get incoming => _incoming.stream;

  bool shouldToast(AppNotification notification) =>
      showRoutineToasts ||
      !(notification.type == NotificationType.servizioIniziato ||
          notification.type == NotificationType.servizioTerminato);

  Future<void> refresh() async {
    final results = await Future.wait<Object>([
      _repository.countUnread(),
      _repository.listNotifications(const NotificationQuery(limit: 12)),
    ]);
    if (_disposed) return;
    _unreadCount = results[0] as int;
    _recent = results[1] as List<AppNotification>;
    notifyListeners();
  }

  Future<void> markRead(String id) async {
    await _repository.markRead(id);
    await refresh();
  }

  Future<void> markAllRead() async {
    await _repository.markAllRead();
    await refresh();
  }

  void setShowRoutineToasts(bool value) {
    showRoutineToasts = value;
    notifyListeners();
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      unawaited(refresh().catchError((Object _) {}));
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    unawaited(_eventSubscription?.cancel());
    unawaited(_newSubscription?.cancel());
    unawaited(_incoming.close());
    super.dispose();
  }
}

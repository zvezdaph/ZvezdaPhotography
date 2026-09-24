import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/clock.dart';
import '../../domain/domain.dart';

/// Contatori delle attività in attesa, mostrati come badge nella barra
/// laterale.
class WorkQueueCounters extends ChangeNotifier {
  WorkQueueCounters({
    required PeopleCareRepositories repositories,
    required this.clock,
  }) : _repositories = repositories {
    _subscription = repositories.events.watchEvents().listen((event) {
      const topics = {
        OperationalEventTopic.servizi,
        OperationalEventTopic.richiesteModifica,
        OperationalEventTopic.documenti,
      };
      if (topics.contains(event.topic)) _scheduleRefresh();
    });
  }

  final PeopleCareRepositories _repositories;
  final Clock clock;
  StreamSubscription<OperationalEvent>? _subscription;
  Timer? _debounce;
  bool _disposed = false;

  int _pendingChangeRequests = 0;
  int _servicesToPlan = 0;
  int _documentsToReview = 0;

  /// Richieste di modifica in attesa di risposta.
  int get pendingChangeRequests => _pendingChangeRequests;

  /// Servizi da assegnare o da riprogrammare nei prossimi 14 giorni.
  int get servicesToPlan => _servicesToPlan;

  /// Documenti ricevuti dal territorio da verificare.
  int get documentsToReview => _documentsToReview;

  Future<void> refresh() async {
    final now = clock.now();
    final results = await Future.wait<Object>([
      _repositories.changeRequests.listChangeRequests(
        const ChangeRequestQuery(statuses: {ChangeRequestStatus.inAttesa}),
      ),
      _repositories.services.searchServices(
        ServiceQuery(
          range: DateRange(startOfDay(now), addDays(startOfDay(now), 14)),
          statuses: const {
            ServiceStatus.daAssegnare,
            ServiceStatus.daRiprogrammare,
          },
        ),
        page: const PageRequest(pageSize: 1),
      ),
      _repositories.documents.searchDocuments(
        const DocumentQuery(pendingReviewOnly: true),
        page: const PageRequest(pageSize: 1),
      ),
    ]);
    if (_disposed) return;
    _pendingChangeRequests = (results[0] as List<ChangeRequest>).length;
    _servicesToPlan = (results[1] as PagedResult<Service>).total;
    _documentsToReview = (results[2] as PagedResult<DocumentInfo>).total;
    notifyListeners();
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(refresh().catchError((Object _) {}));
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

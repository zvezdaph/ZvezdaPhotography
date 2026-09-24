import 'dart:async';

import '../../../core/clock.dart';
import '../../../domain/domain.dart';
import '../../app_state/screen_controller.dart';

/// Schede della coda richieste.
enum RequestTab {
  daGestire('Da gestire'),
  inAttesa('In attesa'),
  chiuse('Chiuse'),
  tutte('Tutte');

  const RequestTab(this.label);

  final String label;

  Set<ChangeRequestStatus> get statuses => switch (this) {
    daGestire => const {
      ChangeRequestStatus.inAttesa,
      ChangeRequestStatus.inLavorazione,
    },
    inAttesa => const {ChangeRequestStatus.inAttesa},
    chiuse => const {ChangeRequestStatus.chiusa},
    tutte => const {},
  };
}

class ChangeRequestsController extends ScreenController {
  ChangeRequestsController({
    required PeopleCareRepositories repositories,
    required this.clock,
  }) : _repositories = repositories,
       super(
         events: repositories.events,
         topics: const {
           OperationalEventTopic.richiesteModifica,
           OperationalEventTopic.servizi,
         },
       );

  final PeopleCareRepositories _repositories;
  final Clock clock;

  RequestTab tab = RequestTab.daGestire;
  Set<ChangeRequestReason> reasons = {};
  String? facilityId;
  String search = '';

  List<ChangeRequest> requests = const [];
  Map<RequestTab, int> counts = const {};
  String? selectedId;

  /// Dettaglio della richiesta selezionata.
  ChangeRequest? selected;
  Service? service;
  List<Service> dayServices = const [];
  Object? detailError;
  bool loadingDetail = false;

  @override
  Future<void> fetch() async {
    final all = await _repositories.changeRequests.listChangeRequests(
      ChangeRequestQuery(
        reasons: reasons,
        facilityId: facilityId,
        search: search.isEmpty ? null : search,
      ),
    );
    counts = {
      for (final t in RequestTab.values)
        t: all
            .where((r) => t.statuses.isEmpty || t.statuses.contains(r.status))
            .length,
    };
    requests = all
        .where((r) => tab.statuses.isEmpty || tab.statuses.contains(r.status))
        .toList();
    // Le richieste in attesa più vecchie per prime: sono le più urgenti.
    if (tab != RequestTab.chiuse && tab != RequestTab.tutte) {
      requests.sort((a, b) {
        final byStatus = a.status.index.compareTo(b.status.index);
        return byStatus != 0 ? byStatus : a.createdAt.compareTo(b.createdAt);
      });
    }
    if (selectedId == null && requests.isNotEmpty) {
      selectedId = requests.first.id;
    }
    await _loadDetail();
  }

  Future<void> _loadDetail() async {
    final id = selectedId;
    if (id == null) {
      selected = null;
      service = null;
      return;
    }
    loadingDetail = true;
    try {
      final request = await _repositories.changeRequests.getChangeRequest(id);
      final svc = await _repositories.services.getService(request.serviceId);
      final day = await _repositories.services.listServicesInRange(
        DateRange.day(svc.scheduledStart),
      );
      selected = request;
      service = svc;
      dayServices = day;
      detailError = null;
    } on RepositoryException catch (error) {
      detailError = error;
    } finally {
      loadingDetail = false;
    }
  }

  Future<void> select(String id) async {
    selectedId = id;
    notifySafely();
    await _loadDetail();
    notifySafely();
  }

  void setTab(RequestTab value) {
    tab = value;
    selectedId = null;
    unawaited(load());
  }

  void setReasons(Set<ChangeRequestReason> value) {
    reasons = value;
    unawaited(load());
  }

  void setFacility(String? value) {
    facilityId = value;
    unawaited(load());
  }

  void setSearch(String value) {
    search = value;
    unawaited(load());
  }

  // Azioni ----------------------------------------------------------------

  Future<ChangeRequest> reply(String message) async {
    final request = selected!;
    final updated = await _repositories.changeRequests.reply(
      request.id,
      message: message,
      expectedVersion: request.version,
    );
    await refresh();
    return updated;
  }

  Future<ChangeRequest> resolve(ChangeRequestResolution resolution) async {
    final request = selected!;
    final updated = await _repositories.changeRequests.resolve(
      request.id,
      resolution,
      expectedVersion: request.version,
    );
    await refresh();
    return updated;
  }

  /// Servizi dell'operatore assegnato che si sovrappongono a [slot].
  List<Service> overlapsFor(DateRange slot, String? operatorId) {
    if (operatorId == null) return const [];
    return const ScheduleConflictDetector().overlapsForSlot(
      operatorId: operatorId,
      slot: slot,
      services: dayServices,
      excludeServiceId: service?.id,
      now: clock.now(),
    );
  }
}

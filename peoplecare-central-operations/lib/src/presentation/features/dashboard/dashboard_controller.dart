import 'dart:async';

import '../../../core/clock.dart';
import '../../../domain/domain.dart';
import '../../app_state/reference_data.dart';
import '../../app_state/screen_controller.dart';

/// Dati della dashboard: situazione di oggi e dei prossimi giorni.
class DashboardController extends ScreenController {
  DashboardController({
    required PeopleCareRepositories repositories,
    required this.clock,
    required this.reference,
  }) : _repositories = repositories,
       super(
         events: repositories.events,
         topics: const {
           OperationalEventTopic.servizi,
           OperationalEventTopic.richiesteModifica,
           OperationalEventTopic.operatori,
         },
       );

  final PeopleCareRepositories _repositories;
  final Clock clock;
  final ReferenceData reference;

  /// Struttura selezionata; `null` = tutte.
  String? facilityId;

  DateTime now = DateTime.now();
  List<Service> today = const [];
  List<Service> window = const [];
  List<Service> toPlan = const [];
  int toPlanTotal = 0;
  List<ChangeRequest> openRequests = const [];
  List<ServiceAlert> alerts = const [];

  Set<String> get _facilities => facilityId == null ? const {} : {facilityId!};

  void setFacility(String? id) {
    facilityId = id;
    unawaited(load());
  }

  @override
  Future<void> fetch() async {
    now = clock.now();
    final day = startOfDay(now);
    final results = await Future.wait<Object>([
      _repositories.services.listServicesInRange(
        DateRange(day, addDays(day, 3)),
        facilityIds: _facilities,
      ),
      _repositories.services.searchServices(
        ServiceQuery(
          range: DateRange(now, addDays(day, 8)),
          facilityIds: _facilities,
          statuses: const {
            ServiceStatus.daAssegnare,
            ServiceStatus.daRiprogrammare,
          },
        ),
        page: const PageRequest(pageSize: 12),
      ),
      _repositories.changeRequests.listChangeRequests(
        ChangeRequestQuery(
          statuses: const {
            ChangeRequestStatus.inAttesa,
            ChangeRequestStatus.inLavorazione,
          },
          facilityId: facilityId,
        ),
      ),
    ]);
    window = results[0] as List<Service>;
    final plan = results[1] as PagedResult<Service>;
    toPlan = plan.items;
    toPlanTotal = plan.total;
    openRequests = results[2] as List<ChangeRequest>;
    today = window
        .where((s) => isSameDay(s.scheduledStart, now))
        .toList(growable: false);
    alerts = const ServiceAlertEvaluator()
        .evaluate(window, now: now, operatorsById: reference.operatorsById)
        .where(
          (a) =>
              // Oggi tutte le anomalie; nei giorni successivi solo quelle
              // che richiedono di pianificare.
              isSameDay(a.service.scheduledStart, now) ||
              a.kind == ServiceAlertKind.sovrapposizione ||
              a.kind == ServiceAlertKind.operatoreNonAttivo,
        )
        .where((a) => a.kind != ServiceAlertKind.richiestaModificaAperta)
        .toList(growable: false);
  }

  // Indicatori ------------------------------------------------------------

  List<Service> get activeToday =>
      today.where((s) => s.status != ServiceStatus.annullato).toList();

  int countToday(ServiceStatus status) =>
      today.where((s) => s.status == status).length;

  int get operatorsOnDuty => today
      .where((s) => s.status == ServiceStatus.inCorso && s.operatorId != null)
      .map((s) => s.operatorId)
      .toSet()
      .length;

  int get pendingRequests => openRequests
      .where((r) => r.status == ChangeRequestStatus.inAttesa)
      .length;

  /// Puntualità dei servizi avviati oggi (entro 10 minuti).
  double? get punctuality {
    final started = today.where((s) => s.actualStart != null).toList();
    if (started.isEmpty) return null;
    final onTime = started.where((s) => s.startDelay!.inMinutes <= 10).length;
    return onTime / started.length;
  }

  double? get averageDelayMinutes {
    final started = today.where((s) => s.actualStart != null).toList();
    if (started.isEmpty) return null;
    return started.fold<int>(0, (sum, s) => sum + s.startDelay!.inMinutes) /
        started.length;
  }

  /// Servizi che iniziano nelle prossime [hours] ore (o in ritardo).
  List<Service> upcoming({int hours = 3}) {
    final limit = now.add(Duration(hours: hours));
    return window
        .where(
          (s) =>
              (s.status == ServiceStatus.assegnato ||
                  s.status == ServiceStatus.daAssegnare) &&
              s.scheduledStart.isBefore(limit) &&
              s.scheduledEnd.isAfter(now),
        )
        .toList()
      ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
  }

  List<Service> get inProgress =>
      today.where((s) => s.status == ServiceStatus.inCorso).toList()
        ..sort((a, b) => a.scheduledEnd.compareTo(b.scheduledEnd));
}

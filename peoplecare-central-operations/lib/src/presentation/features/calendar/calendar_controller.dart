import 'dart:async';

import '../../../core/clock.dart';
import '../../../core/text.dart';
import '../../../domain/domain.dart';
import '../../app_state/reference_data.dart';
import '../../app_state/screen_controller.dart';

enum CalendarView { day, week }

/// Fascia oraria visibile nella vista giorno.
enum HourWindow {
  standard(6, 22, '06–22'),
  diurno(7, 20, '07–20'),
  intera(0, 24, '00–24');

  const HourWindow(this.from, this.to, this.label);

  final int from;
  final int to;
  final String label;
}

/// Riga del calendario: un operatore con i suoi servizi nel periodo.
class CalendarRow {
  const CalendarRow({required this.operator, required this.services});

  final Operator operator;
  final List<Service> services;

  int get activeCount =>
      services.where((s) => s.status != ServiceStatus.annullato).length;

  Duration get plannedDuration => services
      .where((s) => s.status != ServiceStatus.annullato)
      .fold(Duration.zero, (sum, s) => sum + s.scheduledDuration);
}

class CalendarController extends ScreenController {
  CalendarController({
    required PeopleCareRepositories repositories,
    required this.clock,
    required this.reference,
  }) : _repositories = repositories,
       anchor = startOfDay(clock.now()),
       super(
         events: repositories.events,
         topics: const {
           OperationalEventTopic.servizi,
           OperationalEventTopic.operatori,
         },
       );

  final PeopleCareRepositories _repositories;
  final Clock clock;
  final ReferenceData reference;

  CalendarView view = CalendarView.day;
  DateTime anchor;
  String? facilityId;
  String operatorSearch = '';
  bool showCancelled = false;
  bool conflictsOnly = false;
  HourWindow hourWindow = HourWindow.standard;

  List<Service> services = const [];
  Map<String, List<ScheduleConflict>> conflicts = const {};
  DateTime now = DateTime.now();

  DateRange get range =>
      view == CalendarView.day ? DateRange.day(anchor) : DateRange.week(anchor);

  @override
  Future<void> fetch() async {
    now = clock.now();
    // Si caricano tutti i servizi del periodo (anche di altre strutture):
    // servono a mostrare gli impegni reali degli operatori e le
    // sovrapposizioni tra strutture diverse.
    final loaded = await _repositories.services.listServicesInRange(range);
    services = loaded;
    conflicts = const ScheduleConflictDetector().detectByService(
      loaded,
      now: now,
    );
  }

  // Navigazione --------------------------------------------------------------

  void setView(CalendarView value) {
    if (view == value) return;
    view = value;
    unawaited(load());
  }

  void goToday() => goTo(clock.now());

  void goTo(DateTime day) {
    anchor = startOfDay(day);
    unawaited(load());
  }

  void step(int direction) =>
      goTo(addDays(anchor, direction * (view == CalendarView.day ? 1 : 7)));

  void setFacility(String? id) {
    facilityId = id;
    notifySafely();
  }

  void setOperatorSearch(String value) {
    operatorSearch = value;
    notifySafely();
  }

  void setShowCancelled(bool value) {
    showCancelled = value;
    notifySafely();
  }

  void setConflictsOnly(bool value) {
    conflictsOnly = value;
    notifySafely();
  }

  void setHourWindow(HourWindow value) {
    hourWindow = value;
    notifySafely();
  }

  // Dati derivati ---------------------------------------------------------

  bool _visible(Service service) =>
      showCancelled || service.status != ServiceStatus.annullato;

  bool hasConflict(Service service) =>
      conflicts[service.id]?.isNotEmpty ?? false;

  /// Servizi senza operatore nel periodo (filtrati per struttura).
  List<Service> get unassigned =>
      services
          .where(
            (s) =>
                s.operatorId == null &&
                _visible(s) &&
                (facilityId == null || s.facilityId == facilityId),
          )
          .toList()
        ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));

  /// Righe degli operatori da mostrare.
  List<CalendarRow> get rows {
    final byOperator = <String, List<Service>>{};
    for (final service in services) {
      final operatorId = service.operatorId;
      if (operatorId == null || !_visible(service)) continue;
      byOperator.putIfAbsent(operatorId, () => []).add(service);
    }
    final result = <CalendarRow>[];
    for (final operator in reference.operators) {
      final list = byOperator[operator.id] ?? <Service>[];
      if (operator.status == OperatorStatus.disabilitato && list.isEmpty) {
        continue;
      }
      if (facilityId != null &&
          !operator.belongsTo(facilityId!) &&
          !list.any((s) => s.facilityId == facilityId)) {
        continue;
      }
      if (operatorSearch.isNotEmpty &&
          !matchesSearch(operatorSearch, [
            operator.firstName,
            operator.lastName,
            operator.code,
            operator.qualification,
          ])) {
        continue;
      }
      if (conflictsOnly && !list.any(hasConflict)) continue;
      if (operator.status != OperatorStatus.attivo && list.isEmpty) continue;
      result.add(
        CalendarRow(
          operator: operator,
          services: list
            ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart)),
        ),
      );
    }
    return result;
  }

  /// Conteggi per stato nel periodo (con i filtri di struttura).
  Map<ServiceStatus, int> get statusCounts {
    final counts = <ServiceStatus, int>{};
    for (final service in services) {
      if (facilityId != null && service.facilityId != facilityId) continue;
      counts[service.status] = (counts[service.status] ?? 0) + 1;
    }
    return counts;
  }

  int get conflictCount {
    final byId = {for (final s in services) s.id: s};
    final ids = <String>{};
    for (final entry in conflicts.entries) {
      final service = byId[entry.key];
      if (service == null) continue;
      if (facilityId != null && service.facilityId != facilityId) continue;
      if (!service.status.isFinal) ids.add(entry.key);
    }
    return ids.length;
  }

  /// Stato operativo attuale di un operatore (vista giorno di oggi).
  bool isOnDuty(String operatorId) => services.any(
    (s) => s.operatorId == operatorId && s.status == ServiceStatus.inCorso,
  );
}

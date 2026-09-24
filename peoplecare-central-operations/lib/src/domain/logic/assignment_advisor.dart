import '../../core/date_range.dart';
import '../entities/operator.dart';
import '../entities/service.dart';
import 'schedule_conflicts.dart';

/// Valutazione di un operatore per una fascia oraria.
class AssignmentCandidate {
  const AssignmentCandidate({
    required this.operator,
    required this.overlapping,
    required this.belongsToFacility,
    required this.qualificationMatches,
    required this.servicesThatDay,
    required this.plannedThatDay,
  });

  final Operator operator;

  /// Servizi dell'operatore che si sovrappongono alla fascia.
  final List<Service> overlapping;
  final bool belongsToFacility;

  /// `true` anche quando la tipologia non richiede qualifiche.
  final bool qualificationMatches;
  final int servicesThatDay;
  final Duration plannedThatDay;

  bool get isAssignable => operator.isAssignable;

  bool get isFree => overlapping.isEmpty;

  /// Candidato senza alcuna controindicazione.
  bool get isIdeal =>
      isAssignable && isFree && belongsToFacility && qualificationMatches;

  bool get hasWarnings => !isIdeal;
}

/// Ordina gli operatori per idoneità a svolgere un servizio in una fascia.
///
/// Non decide al posto della Centrale: segnala disponibilità, appartenenza
/// alla struttura, qualifica e carico di lavoro della giornata.
class AssignmentAdvisor {
  const AssignmentAdvisor({this.detector = const ScheduleConflictDetector()});

  final ScheduleConflictDetector detector;

  List<AssignmentCandidate> rank({
    required Iterable<Operator> operators,
    required Iterable<Service> services,
    required DateRange slot,
    required String facilityId,
    List<String> requiredQualifications = const [],
    String? excludeServiceId,
    required DateTime now,
    bool includeNotAssignable = false,
  }) {
    final day = DateRange.day(slot.start);
    final serviceList = services.toList();
    final candidates = <AssignmentCandidate>[];
    for (final operator in operators) {
      if (!includeNotAssignable && !operator.isAssignable) continue;
      if (operator.status == OperatorStatus.disabilitato) continue;
      final overlapping = detector.overlapsForSlot(
        operatorId: operator.id,
        slot: slot,
        services: serviceList,
        excludeServiceId: excludeServiceId,
        now: now,
      );
      var count = 0;
      var planned = Duration.zero;
      for (final service in serviceList) {
        if (service.id == excludeServiceId ||
            service.operatorId != operator.id ||
            !service.status.occupiesOperator ||
            !service.scheduledRange.overlaps(day)) {
          continue;
        }
        count++;
        planned += service.scheduledDuration;
      }
      candidates.add(
        AssignmentCandidate(
          operator: operator,
          overlapping: overlapping,
          belongsToFacility: operator.belongsTo(facilityId),
          qualificationMatches:
              requiredQualifications.isEmpty ||
              requiredQualifications.contains(operator.qualification),
          servicesThatDay: count,
          plannedThatDay: planned,
        ),
      );
    }
    candidates.sort(_compare);
    return candidates;
  }

  static int _compare(AssignmentCandidate a, AssignmentCandidate b) {
    int flag(bool value) => value ? 0 : 1;
    final checks = [
      flag(a.isAssignable).compareTo(flag(b.isAssignable)),
      flag(a.isFree).compareTo(flag(b.isFree)),
      flag(a.belongsToFacility).compareTo(flag(b.belongsToFacility)),
      flag(a.qualificationMatches).compareTo(flag(b.qualificationMatches)),
      a.plannedThatDay.compareTo(b.plannedThatDay),
      a.operator.sortName.compareTo(b.operator.sortName),
    ];
    return checks.firstWhere((result) => result != 0, orElse: () => 0);
  }
}

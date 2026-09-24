import '../../core/date_range.dart';
import '../entities/service.dart';

/// Due servizi dello stesso operatore che si sovrappongono.
class ScheduleConflict {
  const ScheduleConflict({
    required this.operatorId,
    required this.first,
    required this.second,
    required this.overlap,
  });

  final String operatorId;
  final Service first;
  final Service second;
  final DateRange overlap;

  bool involves(String serviceId) =>
      first.id == serviceId || second.id == serviceId;

  /// L'altro servizio del conflitto rispetto a [serviceId].
  Service other(String serviceId) => first.id == serviceId ? second : first;
}

/// Individua le sovrapposizioni di orario tra i servizi di uno stesso
/// operatore.
///
/// Contano solo i servizi che impegnano l'operatore (assegnato, in corso,
/// completato), con gli orari reali quando disponibili.
class ScheduleConflictDetector {
  const ScheduleConflictDetector();

  List<ScheduleConflict> detect(
    Iterable<Service> services, {
    required DateTime now,
  }) {
    final byOperator = <String, List<(Service, DateRange)>>{};
    for (final service in services) {
      final operatorId = service.operatorId;
      if (operatorId == null || !service.status.occupiesOperator) continue;
      byOperator.putIfAbsent(operatorId, () => []).add((
        service,
        service.occupiedRange(now),
      ));
    }

    final conflicts = <ScheduleConflict>[];
    for (final MapEntry(key: operatorId, value: items) in byOperator.entries) {
      items.sort((a, b) => a.$2.start.compareTo(b.$2.start));
      for (var i = 0; i < items.length; i++) {
        final (first, firstRange) = items[i];
        for (var j = i + 1; j < items.length; j++) {
          final (second, secondRange) = items[j];
          // Ordinati per inizio: i successivi iniziano ancora più tardi.
          if (!secondRange.start.isBefore(firstRange.end)) break;
          final overlap = firstRange.intersection(secondRange);
          if (overlap != null && overlap.duration > Duration.zero) {
            conflicts.add(
              ScheduleConflict(
                operatorId: operatorId,
                first: first,
                second: second,
                overlap: overlap,
              ),
            );
          }
        }
      }
    }
    return conflicts;
  }

  /// Conflitti indicizzati per ID servizio.
  Map<String, List<ScheduleConflict>> detectByService(
    Iterable<Service> services, {
    required DateTime now,
  }) {
    final result = <String, List<ScheduleConflict>>{};
    for (final conflict in detect(services, now: now)) {
      result.putIfAbsent(conflict.first.id, () => []).add(conflict);
      result.putIfAbsent(conflict.second.id, () => []).add(conflict);
    }
    return result;
  }

  /// Servizi di [operatorId] che si sovrappongono a [slot], escluso
  /// [excludeServiceId] (il servizio che si sta spostando).
  List<Service> overlapsForSlot({
    required String operatorId,
    required DateRange slot,
    required Iterable<Service> services,
    String? excludeServiceId,
    required DateTime now,
  }) {
    return [
      for (final service in services)
        if (service.id != excludeServiceId &&
            service.operatorId == operatorId &&
            service.status.occupiesOperator &&
            service.occupiedRange(now).overlaps(slot))
          service,
    ]..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
  }
}

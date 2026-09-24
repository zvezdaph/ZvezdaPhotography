import '../../core/date_range.dart';
import '../entities/change_request.dart';
import '../entities/facility.dart';
import '../entities/operator.dart';
import '../entities/report.dart';
import '../entities/service.dart';

/// Calcola il report operativo a partire dai servizi.
///
/// Il mock lo usa per simulare l'endpoint di reportistica; un'implementazione
/// reale può riusarlo se il sistema PeopleCare non fornisce aggregati.
class ReportCalculator {
  const ReportCalculator({this.onTimeToleranceMinutes = 10});

  /// Tolleranza entro cui un avvio è considerato puntuale.
  final int onTimeToleranceMinutes;

  OperationalReport compute({
    required ReportQuery query,
    required Iterable<Service> services,
    required Iterable<ChangeRequest> changeRequests,
    required Map<String, Operator> operatorsById,
    required Map<String, Facility> facilitiesById,
    required DateTime generatedAt,
  }) {
    final included = [
      for (final service in services)
        if (query.period.contains(service.scheduledStart) &&
            (query.facilityId == null ||
                service.facilityId == query.facilityId))
          service,
    ];
    final includedIds = {for (final service in included) service.id};

    final byStatus = {for (final status in ServiceStatus.values) status: 0};
    var started = 0;
    var onTime = 0;
    var delaySum = 0;
    var scheduledMinutes = 0;
    var deliveredMinutes = 0;

    final daily = <DateTime, Map<ServiceStatus, int>>{
      for (final day in query.period.days)
        day: {for (final status in ServiceStatus.values) status: 0},
    };
    final operatorAcc = <String, _Accumulator>{};
    final typeAcc = <String, _Accumulator>{};
    final typeLabels = <String, String>{};
    final facilityAcc = <String, _Accumulator>{};

    for (final service in included) {
      byStatus[service.status] = byStatus[service.status]! + 1;
      final day = startOfDay(service.scheduledStart);
      final dayCounts = daily[day];
      if (dayCounts != null) {
        dayCounts[service.status] = dayCounts[service.status]! + 1;
      }

      final cancelled = service.status == ServiceStatus.annullato;
      final scheduled = cancelled ? 0 : service.scheduledDuration.inMinutes;
      final delivered = service.status == ServiceStatus.completato
          ? (service.actualDuration?.inMinutes ?? 0)
          : 0;
      scheduledMinutes += scheduled;
      deliveredMinutes += delivered;

      final delay = service.startDelay;
      if (delay != null) {
        started++;
        delaySum += delay.inMinutes;
        if (delay.inMinutes <= onTimeToleranceMinutes) onTime++;
      }

      final operatorId = service.operatorId;
      if (operatorId != null) {
        operatorAcc
            .putIfAbsent(operatorId, _Accumulator.new)
            .add(service, scheduled, delivered);
      }
      final typeKey = service.serviceTypeId ?? '_custom';
      typeLabels[typeKey] = service.serviceTypeId == null
          ? 'Servizi personalizzati'
          : service.kind.label;
      typeAcc
          .putIfAbsent(typeKey, _Accumulator.new)
          .add(service, scheduled, delivered);
      facilityAcc
          .putIfAbsent(service.facilityId, _Accumulator.new)
          .add(service, scheduled, delivered);
    }

    final requestsByReason = {
      for (final reason in ChangeRequestReason.values) reason: 0,
    };
    var requestCount = 0;
    for (final request in changeRequests) {
      if (!includedIds.contains(request.serviceId)) continue;
      requestCount++;
      requestsByReason[request.reason] = requestsByReason[request.reason]! + 1;
    }

    final operatorRows = [
      for (final MapEntry(key: id, value: acc) in operatorAcc.entries)
        OperatorReportRow(
          operatorId: id,
          operatorName: operatorsById[id]?.fullName ?? 'Operatore $id',
          operatorCode: operatorsById[id]?.code ?? '',
          totalServices: acc.total,
          completed: acc.completed,
          notExecuted: acc.notExecuted,
          cancelled: acc.cancelled,
          scheduledMinutes: acc.scheduledMinutes,
          deliveredMinutes: acc.deliveredMinutes,
          averageStartDelayMinutes: acc.averageDelay,
        ),
    ]..sort((a, b) => b.deliveredMinutes.compareTo(a.deliveredMinutes));

    final typeRows = [
      for (final MapEntry(key: key, value: acc) in typeAcc.entries)
        ServiceTypeReportRow(
          label: typeLabels[key]!,
          serviceTypeId: key == '_custom' ? null : key,
          totalServices: acc.total,
          completed: acc.completed,
          deliveredMinutes: acc.deliveredMinutes,
        ),
    ]..sort((a, b) => b.totalServices.compareTo(a.totalServices));

    final facilityRows = [
      for (final MapEntry(key: id, value: acc) in facilityAcc.entries)
        FacilityReportRow(
          facilityId: id,
          facilityName: facilitiesById[id]?.name ?? id,
          totalServices: acc.total,
          completed: acc.completed,
          deliveredMinutes: acc.deliveredMinutes,
        ),
    ]..sort((a, b) => b.totalServices.compareTo(a.totalServices));

    return OperationalReport(
      period: query.period,
      facilityId: query.facilityId,
      generatedAt: generatedAt,
      totalServices: included.length,
      byStatus: byStatus,
      startedServices: started,
      onTimeStarts: onTime,
      onTimeToleranceMinutes: onTimeToleranceMinutes,
      averageStartDelayMinutes: started == 0 ? null : delaySum / started,
      scheduledMinutes: scheduledMinutes,
      deliveredMinutes: deliveredMinutes,
      changeRequestCount: requestCount,
      changeRequestsByReason: requestsByReason,
      daily: [
        for (final MapEntry(key: day, value: counts) in daily.entries)
          DailyServiceStat(day: day, byStatus: counts),
      ]..sort((a, b) => a.day.compareTo(b.day)),
      operators: operatorRows,
      serviceTypes: typeRows,
      facilities: facilityRows,
    );
  }
}

class _Accumulator {
  int total = 0;
  int completed = 0;
  int notExecuted = 0;
  int cancelled = 0;
  int scheduledMinutes = 0;
  int deliveredMinutes = 0;
  int _delaySum = 0;
  int _started = 0;

  void add(Service service, int scheduled, int delivered) {
    total++;
    switch (service.status) {
      case ServiceStatus.completato:
        completed++;
      case ServiceStatus.nonEseguito:
        notExecuted++;
      case ServiceStatus.annullato:
        cancelled++;
      default:
        break;
    }
    scheduledMinutes += scheduled;
    deliveredMinutes += delivered;
    final delay = service.startDelay;
    if (delay != null) {
      _started++;
      _delaySum += delay.inMinutes;
    }
  }

  double? get averageDelay => _started == 0 ? null : _delaySum / _started;
}

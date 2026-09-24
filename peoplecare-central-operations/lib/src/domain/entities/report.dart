import '../../core/date_range.dart';
import 'change_request.dart';
import 'service.dart';

/// Parametri del report operativo.
class ReportQuery {
  const ReportQuery({required this.period, this.facilityId});

  final DateRange period;

  /// Struttura su cui filtrare; `null` = tutte.
  final String? facilityId;
}

/// Andamento giornaliero dei servizi.
class DailyServiceStat {
  const DailyServiceStat({required this.day, required this.byStatus});

  final DateTime day;
  final Map<ServiceStatus, int> byStatus;

  int get total => byStatus.values.fold(0, (sum, value) => sum + value);

  int count(ServiceStatus status) => byStatus[status] ?? 0;
}

/// Riga del report per operatore.
class OperatorReportRow {
  const OperatorReportRow({
    required this.operatorId,
    required this.operatorName,
    required this.operatorCode,
    required this.totalServices,
    required this.completed,
    required this.notExecuted,
    required this.cancelled,
    required this.scheduledMinutes,
    required this.deliveredMinutes,
    this.averageStartDelayMinutes,
  });

  final String operatorId;
  final String operatorName;
  final String operatorCode;
  final int totalServices;
  final int completed;
  final int notExecuted;
  final int cancelled;

  /// Minuti programmati (servizi non annullati).
  final int scheduledMinutes;

  /// Minuti effettivi (da `actual_start`/`actual_end`).
  final int deliveredMinutes;

  /// Ritardo medio di avvio; `null` se nessun servizio avviato.
  final double? averageStartDelayMinutes;
}

/// Riga del report per tipologia di servizio.
class ServiceTypeReportRow {
  const ServiceTypeReportRow({
    required this.label,
    this.serviceTypeId,
    required this.totalServices,
    required this.completed,
    required this.deliveredMinutes,
  });

  final String label;

  /// `null` per i servizi personalizzati (raggruppati insieme).
  final String? serviceTypeId;
  final int totalServices;
  final int completed;
  final int deliveredMinutes;
}

/// Riga del report per struttura.
class FacilityReportRow {
  const FacilityReportRow({
    required this.facilityId,
    required this.facilityName,
    required this.totalServices,
    required this.completed,
    required this.deliveredMinutes,
  });

  final String facilityId;
  final String facilityName;
  final int totalServices;
  final int completed;
  final int deliveredMinutes;
}

/// Report operativo di un periodo, calcolato sui servizi programmati nel
/// periodo e sugli orari reali registrati dall'app mobile.
class OperationalReport {
  const OperationalReport({
    required this.period,
    this.facilityId,
    required this.generatedAt,
    required this.totalServices,
    required this.byStatus,
    required this.startedServices,
    required this.onTimeStarts,
    required this.onTimeToleranceMinutes,
    this.averageStartDelayMinutes,
    required this.scheduledMinutes,
    required this.deliveredMinutes,
    required this.changeRequestCount,
    required this.changeRequestsByReason,
    required this.daily,
    required this.operators,
    required this.serviceTypes,
    required this.facilities,
  });

  final DateRange period;
  final String? facilityId;
  final DateTime generatedAt;
  final int totalServices;
  final Map<ServiceStatus, int> byStatus;

  /// Servizi con `actual_start` valorizzato.
  final int startedServices;

  /// Servizi avviati entro [onTimeToleranceMinutes] dall'inizio programmato.
  final int onTimeStarts;
  final int onTimeToleranceMinutes;

  /// Ritardo medio di avvio (minuti, negativo = in anticipo).
  final double? averageStartDelayMinutes;
  final int scheduledMinutes;
  final int deliveredMinutes;
  final int changeRequestCount;
  final Map<ChangeRequestReason, int> changeRequestsByReason;
  final List<DailyServiceStat> daily;
  final List<OperatorReportRow> operators;
  final List<ServiceTypeReportRow> serviceTypes;
  final List<FacilityReportRow> facilities;

  int count(ServiceStatus status) => byStatus[status] ?? 0;

  /// Completati sul totale dei servizi non annullati e già conclusi o scaduti.
  double? get completionRate {
    final concluded =
        count(ServiceStatus.completato) + count(ServiceStatus.nonEseguito);
    if (concluded == 0) return null;
    return count(ServiceStatus.completato) / concluded;
  }

  double? get punctualityRate =>
      startedServices == 0 ? null : onTimeStarts / startedServices;
}

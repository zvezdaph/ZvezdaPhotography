import '../entities/operator.dart';
import '../entities/service.dart';
import 'schedule_conflicts.dart';

/// Tipo di anomalia operativa rilevata su un servizio.
enum ServiceAlertKind {
  /// Non avviato oltre la tolleranza dall'inizio programmato.
  avvioInRitardo,

  /// In corso oltre la fine programmata.
  sforamento,

  /// Sovrapposto a un altro servizio dello stesso operatore.
  sovrapposizione,

  /// Senza operatore e in partenza a breve (o già iniziato).
  daAssegnareImminente,

  /// In attesa di un nuovo orario.
  daRiprogrammare,

  /// Non eseguito.
  nonEseguito,

  /// Assegnato a un operatore sospeso o disabilitato.
  operatoreNonAttivo,

  /// Con richieste di modifica aperte.
  richiestaModificaAperta,
}

/// Livello di gravità dell'anomalia.
enum AlertLevel { attenzione, critico }

/// Anomalia su un servizio.
class ServiceAlert {
  const ServiceAlert({
    required this.kind,
    required this.level,
    required this.service,
    this.delay,
    this.otherService,
  });

  final ServiceAlertKind kind;
  final AlertLevel level;
  final Service service;

  /// Ritardo di avvio o sforamento, quando pertinente.
  final Duration? delay;

  /// Servizio in sovrapposizione.
  final Service? otherService;
}

/// Calcola le anomalie operative da mostrare in dashboard e calendario.
class ServiceAlertEvaluator {
  const ServiceAlertEvaluator({
    this.lateStartTolerance = const Duration(minutes: 10),
    this.criticalLateStart = const Duration(minutes: 30),
    this.overrunTolerance = const Duration(minutes: 15),
    this.imminentWindow = const Duration(hours: 24),
    this.criticalImminentWindow = const Duration(hours: 2),
    this.detector = const ScheduleConflictDetector(),
  });

  final Duration lateStartTolerance;
  final Duration criticalLateStart;
  final Duration overrunTolerance;
  final Duration imminentWindow;
  final Duration criticalImminentWindow;
  final ScheduleConflictDetector detector;

  List<ServiceAlert> evaluate(
    Iterable<Service> services, {
    required DateTime now,
    Map<String, Operator> operatorsById = const {},
  }) {
    final list = services.toList();
    final alerts = <ServiceAlert>[];

    for (final service in list) {
      switch (service.status) {
        case ServiceStatus.assegnato:
          final late = now.difference(service.scheduledStart);
          if (service.actualStart == null && late > lateStartTolerance) {
            alerts.add(
              ServiceAlert(
                kind: ServiceAlertKind.avvioInRitardo,
                level: late > criticalLateStart
                    ? AlertLevel.critico
                    : AlertLevel.attenzione,
                service: service,
                delay: late,
              ),
            );
          }
        case ServiceStatus.inCorso:
          final overrun = now.difference(service.scheduledEnd);
          if (overrun > overrunTolerance) {
            alerts.add(
              ServiceAlert(
                kind: ServiceAlertKind.sforamento,
                level: AlertLevel.attenzione,
                service: service,
                delay: overrun,
              ),
            );
          }
        case ServiceStatus.daAssegnare:
          final untilStart = service.scheduledStart.difference(now);
          if (untilStart <= imminentWindow &&
              service.scheduledEnd.isAfter(now)) {
            alerts.add(
              ServiceAlert(
                kind: ServiceAlertKind.daAssegnareImminente,
                level: untilStart <= criticalImminentWindow
                    ? AlertLevel.critico
                    : AlertLevel.attenzione,
                service: service,
              ),
            );
          }
        case ServiceStatus.daRiprogrammare:
          alerts.add(
            ServiceAlert(
              kind: ServiceAlertKind.daRiprogrammare,
              level: AlertLevel.attenzione,
              service: service,
            ),
          );
        case ServiceStatus.nonEseguito:
          alerts.add(
            ServiceAlert(
              kind: ServiceAlertKind.nonEseguito,
              level: AlertLevel.attenzione,
              service: service,
            ),
          );
        case ServiceStatus.completato:
        case ServiceStatus.annullato:
          break;
      }

      final operator = service.operatorId == null
          ? null
          : operatorsById[service.operatorId];
      if (operator != null &&
          !operator.isAssignable &&
          !service.status.isFinal) {
        alerts.add(
          ServiceAlert(
            kind: ServiceAlertKind.operatoreNonAttivo,
            level: AlertLevel.critico,
            service: service,
          ),
        );
      }

      if (service.openChangeRequestCount > 0 && !service.status.isFinal) {
        alerts.add(
          ServiceAlert(
            kind: ServiceAlertKind.richiestaModificaAperta,
            level: AlertLevel.attenzione,
            service: service,
          ),
        );
      }
    }

    // Sovrapposizioni ancora rilevanti (servizi non conclusi).
    for (final conflict in detector.detect(list, now: now)) {
      if (conflict.first.status == ServiceStatus.completato &&
          conflict.second.status == ServiceStatus.completato) {
        continue;
      }
      alerts.add(
        ServiceAlert(
          kind: ServiceAlertKind.sovrapposizione,
          level: AlertLevel.critico,
          service: conflict.first,
          otherService: conflict.second,
        ),
      );
    }

    alerts.sort((a, b) {
      final level = b.level.index.compareTo(a.level.index);
      if (level != 0) return level;
      return a.service.scheduledStart.compareTo(b.service.scheduledStart);
    });
    return alerts;
  }
}

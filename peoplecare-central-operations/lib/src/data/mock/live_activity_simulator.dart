import 'dart:async';
import 'dart:math';

import '../../domain/domain.dart';
import 'mock_backend.dart';

/// Simula ciò che faranno gli operatori dall'app mobile mentre la demo è
/// aperta: avvio e chiusura dei servizi all'orario previsto, qualche mancata
/// esecuzione, nuove richieste di modifica e documenti inviati dal territorio.
/// SOLO DEMO.
class LiveActivitySimulator {
  LiveActivitySimulator(
    this.backend, {
    this.interval = const Duration(seconds: 15),
    int seed = 4242,
  }) : _random = Random(seed);

  final MockBackend backend;
  final Duration interval;
  final Random _random;
  Timer? _timer;

  bool get isRunning => _timer != null;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Un passo di simulazione (esposto per i test).
  void tick() {
    final now = backend.now;
    for (final service in backend.services.values.toList()) {
      switch (service.status) {
        case ServiceStatus.assegnato:
          _handleAssigned(service, now);
        case ServiceStatus.inCorso:
          final due = service.scheduledEnd.add(
            Duration(minutes: _offset(service, -5, 10)),
          );
          if (!now.isBefore(due)) {
            backend.completeServiceFromMobile(service.id, now);
          }
        default:
          break;
      }
    }
    if (_random.nextDouble() < 0.05) _randomChangeRequest(now);
    if (_random.nextDouble() < 0.05) _randomDocument(now);
  }

  void _handleAssigned(Service service, DateTime now) {
    final late = now.difference(service.scheduledStart);
    final stalled = backend.stalledServiceIds.contains(service.id);
    if (!stalled && now.isBefore(service.scheduledEnd)) {
      final due = service.scheduledStart.add(
        Duration(minutes: _offset(service, -3, 8)),
      );
      if (!now.isBefore(due)) {
        if (_random.nextDouble() < 0.03) {
          backend.markNotExecutedFromMobile(
            service.id,
            now,
            'Paziente assente al domicilio',
          );
        } else {
          backend.startServiceFromMobile(service.id, now);
        }
        return;
      }
    }
    if (late > const Duration(minutes: 15) &&
        now.isBefore(service.scheduledEnd)) {
      backend.notifyLateStart(service);
    }
  }

  /// Scostamento deterministico (in minuti) per servizio.
  int _offset(Service service, int min, int max) {
    final hash = service.id.codeUnits.fold<int>(
      7,
      (acc, unit) => (acc * 31 + unit) & 0x7fffffff,
    );
    return min + hash % (max - min + 1);
  }

  static const _requests = <(ChangeRequestReason, String)>[
    (
      ChangeRequestReason.problemaOrario,
      'La famiglia chiede di anticipare di mezz\'ora, è possibile?',
    ),
    (
      ChangeRequestReason.imprevisto,
      'Ho avuto un contrattempo con l\'auto, rischio di arrivare in ritardo.',
    ),
    (
      ChangeRequestReason.indisponibilita,
      'Domani ho una visita medica in quella fascia oraria.',
    ),
    (
      ChangeRequestReason.problemaLogistico,
      'Il paziente è ospite dalla figlia in un altro comune per qualche giorno.',
    ),
    (
      ChangeRequestReason.altro,
      'Il paziente chiede di confermare l\'orario per telefono.',
    ),
  ];

  void _randomChangeRequest(DateTime now) {
    final candidates =
        backend.services.values
            .where(
              (s) =>
                  s.status == ServiceStatus.assegnato &&
                  s.operatorId != null &&
                  backend.operators[s.operatorId]?.isAssignable == true &&
                  s.openChangeRequestCount == 0 &&
                  s.scheduledStart.isAfter(now.add(const Duration(hours: 3))) &&
                  s.scheduledStart.isBefore(now.add(const Duration(hours: 48))),
            )
            .toList()
          ..sort((a, b) => a.code.compareTo(b.code));
    if (candidates.isEmpty) return;
    final service = candidates[_random.nextInt(candidates.length)];
    final (reason, message) = _requests[_random.nextInt(_requests.length)];
    final proposed = reason == ChangeRequestReason.problemaOrario
        ? service.scheduledStart.subtract(const Duration(minutes: 30))
        : null;
    backend.submitChangeRequestFromMobile(
      serviceId: service.id,
      reason: reason,
      message: message,
      proposedStart: proposed,
      proposedEnd: proposed?.add(service.scheduledDuration),
      at: now,
    );
  }

  void _randomDocument(DateTime now) {
    final candidates =
        backend.services.values
            .where(
              (s) =>
                  s.status == ServiceStatus.completato &&
                  s.documentCount == 0 &&
                  s.actualEnd != null &&
                  now.difference(s.actualEnd!) < const Duration(hours: 2),
            )
            .toList()
          ..sort((a, b) => a.code.compareTo(b.code));
    if (candidates.isEmpty) return;
    final service = candidates[_random.nextInt(candidates.length)];
    backend.receiveDocumentFromMobile(
      owner: DocumentOwner(type: DocumentOwnerType.servizio, id: service.id),
      operatorId: service.operatorId!,
      title: 'Foglio firma prestazione',
      fileName: 'foglio_firma_${service.code.toLowerCase()}.pdf',
      category: DocumentCategory.foglioFirma,
      sizeBytes: (90 + _random.nextInt(300)) * 1024,
      at: now,
    );
  }
}

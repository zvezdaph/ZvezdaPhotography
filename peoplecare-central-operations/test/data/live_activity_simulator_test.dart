import 'package:flutter_test/flutter_test.dart';
import 'package:peoplecare_central_operations/src/core/clock.dart';
import 'package:peoplecare_central_operations/src/data/mock/live_activity_simulator.dart';
import 'package:peoplecare_central_operations/src/domain/domain.dart';

import '../support/test_support.dart';

void main() {
  test('con il passare del tempo i servizi vengono avviati e chiusi', () async {
    final clock = FixedClock(testNow);
    final backend = createSeededBackend(clock: clock);
    final simulator = LiveActivitySimulator(backend);
    final notifications = <AppNotification>[];
    final subscription = backend.newNotifications.listen(notifications.add);

    int count(ServiceStatus status) =>
        backend.services.values.where((s) => s.status == status).length;
    final completedBefore = count(ServiceStatus.completato);

    // Mezza giornata simulata a passi di 5 minuti.
    for (var i = 0; i < 12 * 6; i++) {
      clock.advance(const Duration(minutes: 5));
      simulator.tick();
    }
    await Future<void>.delayed(Duration.zero);

    expect(count(ServiceStatus.completato), greaterThan(completedBefore));
    expect(
      notifications.map((n) => n.type),
      containsAll([
        NotificationType.servizioIniziato,
        NotificationType.servizioTerminato,
      ]),
    );
    for (final service in backend.services.values) {
      if (service.status == ServiceStatus.completato) {
        expect(service.actualEnd!.isAfter(clock.now()), isFalse);
      }
    }
    await subscription.cancel();
    await backend.dispose();
  });
}

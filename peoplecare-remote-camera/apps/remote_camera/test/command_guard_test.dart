import 'package:flutter_test/flutter_test.dart';
import 'package:remote_camera/src/protocol/command_guard.dart';
import 'package:remote_camera/src/protocol/protocol.dart';

DeviceCommand command(String id, int seq, {int sentAt = 1000, int ttl = 15000}) => DeviceCommand(
      commandId: id,
      seq: seq,
      command: 'pause',
      value: null,
      issuedAt: sentAt,
      sentAt: sentAt,
      expiresAt: sentAt + ttl,
      issuedBy: 'test',
    );

void main() {
  group('anti replay', () {
    test('accepts new commands in sequence', () {
      final guard = CommandGuard()..startSession('conn_a');
      expect(guard.check(command('aaaaaaaaaaaaaaaa01', 1), 1000), isA<Accepted>());
      expect(guard.check(command('aaaaaaaaaaaaaaaa02', 2), 1000), isA<Accepted>());
      expect(guard.lastSeq, 2);
    });

    test('refuses an already executed command id', () {
      final guard = CommandGuard()..startSession('conn_a');
      guard.check(command('aaaaaaaaaaaaaaaa01', 1), 1000);
      final result = guard.check(command('aaaaaaaaaaaaaaaa01', 5), 1000);
      expect(result, isA<Rejected>());
      expect((result as Rejected).code, 'duplicate_command');
    });

    test('refuses old sequence numbers within a session', () {
      final guard = CommandGuard()..startSession('conn_a');
      guard.check(command('aaaaaaaaaaaaaaaa01', 10), 1000);
      final result = guard.check(command('aaaaaaaaaaaaaaaa02', 9), 1000);
      expect((result as Rejected).code, 'replay_rejected');
    });

    test('restarts the sequence on a new session but keeps remembered ids', () {
      final guard = CommandGuard()..startSession('conn_a');
      guard.check(command('aaaaaaaaaaaaaaaa01', 10), 1000);
      guard.startSession('conn_b');
      expect(guard.check(command('aaaaaaaaaaaaaaaa02', 1), 1000), isA<Accepted>());
      expect(guard.check(command('aaaaaaaaaaaaaaaa01', 2), 1000), isA<Rejected>());
    });

    test('refuses expired commands using the server clock', () {
      final guard = CommandGuard(toleranceMs: 0)..startSession('conn_a');
      // Local clock is 10 minutes behind the server.
      guard.serverOffsetMs = 600000;
      final localNow = 1000;
      final sent = localNow + 600000;
      expect(guard.check(command('aaaaaaaaaaaaaaaa01', 1, sentAt: sent), localNow), isA<Accepted>());
      final expired = guard.check(command('aaaaaaaaaaaaaaaa02', 2, sentAt: sent - 20000), localNow);
      expect((expired as Rejected).code, 'command_expired');
    });

    test('estimates the clock offset from ping/pong', () {
      final guard = CommandGuard();
      guard.updateOffset(serverTime: 10500, sentAtLocal: 1000, receivedAtLocal: 1200);
      expect(guard.serverOffsetMs, 10500 + 100 - 1200);
      guard.updateOffset(serverTime: 0, sentAtLocal: 5000, receivedAtLocal: 1000); // negative rtt ignored
      expect(guard.serverOffsetMs, 10500 + 100 - 1200);
    });

    test('bounds the memory of remembered ids', () {
      final guard = CommandGuard(maxRemembered: 3)..startSession('c');
      for (var i = 1; i <= 5; i++) {
        guard.check(command('aaaaaaaaaaaaaaaa0$i', i), 1000);
      }
      guard.startSession('d');
      // id 1 was evicted, id 5 is still remembered
      expect(guard.check(command('aaaaaaaaaaaaaaaa01', 1), 1000), isA<Accepted>());
      expect(guard.check(command('aaaaaaaaaaaaaaaa05', 2), 1000), isA<Rejected>());
    });
  });
}

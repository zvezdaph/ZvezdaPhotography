import 'package:flutter_test/flutter_test.dart';
import 'package:remote_camera/src/protocol/protocol.dart';

import 'support/fixtures.dart';

void main() {
  group('JSON command protocol', () {
    test('parses the golden device command', () {
      final command = DeviceCommand.parse(fixture('device_command.json'));
      expect(command.command, 'set_zoom');
      expect(command.value, 2.5);
      expect(command.seq, 42);
      expect(command.expiresAt - command.sentAt, 15000);
      expect(command.issuedBy, 'Regia');
    });

    test('builds ACKs identical to the golden fixtures', () {
      final received = fixture('ack_received.json');
      expect(Outgoing.ackReceived(received['commandId'] as String, received['ts'] as int), received);
      final ok = fixture('ack_completed_ok.json');
      expect(
        Outgoing.ackCompleted(ok['commandId'] as String, (ok['result'] as Map).cast<String, Object?>(), ok['ts'] as int),
        ok,
      );
      final failed = fixture('ack_completed_error.json');
      final error = (failed['error'] as Map).cast<String, Object?>();
      expect(
        Outgoing.ackFailed(failed['commandId'] as String, error['code'] as String, error['message'] as String, failed['ts'] as int),
        failed,
      );
    });

    test('rejects unknown commands, versions and ids', () {
      final base = fixture('device_command.json');
      expect(() => DeviceCommand.parse({...base, 'v': 2}), throwsA(isA<ProtocolException>()));
      expect(() => DeviceCommand.parse({...base, 'command': 'format_disk'}), throwsA(isA<ProtocolException>()));
      expect(() => DeviceCommand.parse({...base, 'commandId': 'x'}), throwsA(isA<ProtocolException>()));
      expect(() => DeviceCommand.parse({...base, 'seq': 'one'}), throwsA(isA<ProtocolException>()));
    });

    test('validates the same invalid values as the server', () {
      for (final entry in fixtureList('invalid_command_requests.json')) {
        final message = ((entry as Map)['message'] as Map).cast<String, Object?>();
        final command = message['command'] as String;
        if (!commandNames.contains(command)) continue;
        if (message['v'] != 1 || (message['commandId'] as String).length < 16) continue;
        if (entry['reason'] == 'stale timestamp') continue; // checked by the server clock
        expect(
          () => validateCommandValue(command, message['value']),
          throwsA(isA<ProtocolException>()),
          reason: entry['reason'] as String,
        );
      }
    });

    test('normalizes values like the server', () {
      expect(validateCommandValue('set_zoom', 2.345), 2.35);
      expect(validateCommandValue('set_bitrate', {'mode': 'manual', 'kbps': 4999.6}), {'mode': 'manual', 'kbps': 5000});
      expect(validateCommandValue('set_bitrate', {'mode': 'auto'}), {'mode': 'auto'});
      expect(validateCommandValue('focus_point', {'x': 0.25, 'y': 1}), {'x': 0.25, 'y': 1.0});
      expect(validateCommandValue('pause', null), isNull);
      expect(() => validateCommandValue('set_exposure', 1.5), throwsA(isA<ProtocolException>()));
    });

    test('every command of the protocol has a validator', () {
      const samples = <String, Object?>{
        'switch_camera': 'front',
        'set_zoom': 1,
        'set_audio_enabled': true,
        'set_video_enabled': false,
        'set_torch': true,
        'set_autofocus': true,
        'focus_point': {'x': 0.5, 'y': 0.5},
        'set_exposure': 2,
        'set_resolution': '720p',
        'set_fps': 25,
        'set_bitrate': {'mode': 'manual', 'kbps': 3000},
        'set_preset': 'standard',
        'set_record': true,
      };
      for (final command in commandNames) {
        expect(() => validateCommandValue(command, samples[command]), returnsNormally, reason: command);
      }
    });

    test('outgoing messages carry the protocol version', () {
      expect(Outgoing.ping(1)['v'], protocolVersion);
      expect(Outgoing.configRequest(), {'v': 1, 'type': 'config_request'});
      expect(Outgoing.state({'a': 1}).containsKey('capabilities'), isFalse);
      expect(Outgoing.state({'a': 1}, capabilities: {'b': 2})['capabilities'], {'b': 2});
    });
  });
}

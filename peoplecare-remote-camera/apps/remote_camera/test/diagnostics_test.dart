import 'package:flutter_test/flutter_test.dart';
import 'package:remote_camera/src/logging/app_logger.dart';
import 'package:remote_camera/src/logging/diagnostics.dart';

void main() {
  group('log redaction', () {
    test('removes SRT secrets, bearer tokens and stream keys', () {
      const text = 'srt://live.example.invalid:778?streamid=0123456789abcdef&passphrase=super-secret-pass&latency=500 '
          'Authorization: Bearer device-token-0123456789-abcdefghij '
          'rtmps://live.example.invalid:443/live/streamkey1234567890 '
          '{"deviceToken":"abc123def456ghi789","passphrase":"x"}';
      final out = Redactor.redact(text);
      expect(out, isNot(contains('super-secret-pass')));
      expect(out, isNot(contains('0123456789abcdef&')));
      expect(out, isNot(contains('device-token-0123456789')));
      expect(out, isNot(contains('streamkey1234567890')));
      expect(out, isNot(contains('abc123def456ghi789')));
      expect(out, contains('live.example.invalid:778'));
      expect(out, contains('latency=500'));
    });

    test('logger keeps a bounded ring buffer and redacts on write', () {
      final logger = AppLogger(capacity: 3);
      for (var i = 0; i < 5; i++) {
        logger.info('t', 'message $i');
      }
      logger.error('t', 'passphrase=abcdefghijklmnop');
      expect(logger.entries, hasLength(3));
      expect(logger.entries.last.message, 'passphrase=***');
      expect(logger.recent(minLevel: LogLevel.error), hasLength(1));
    });
  });

  group('diagnostic report', () {
    test('contains states and logs but no secrets', () {
      final logger = AppLogger()..warning('stream', 'Connessione srt://h:778?streamid=abcdefgh&passphrase=0123456789abc');
      final report = DiagnosticsReport.build(
        now: DateTime.utc(2026, 9, 24, 10),
        app: {'versione': '1.0.0', 'token': 'device-token-0123456789-abcdefghij'},
        device: {'modello': 'Pixel'},
        engine: {'stream': 'live'},
        control: {'regia': 'connected'},
        logs: logger.entries,
      );
      expect(report, contains('PeopleCare Remote Camera'));
      expect(report, contains('stream: live'));
      expect(report, contains('WARNING'));
      expect(report, isNot(contains('0123456789abc')));
      expect(report, isNot(contains('device-token-0123456789-abcdefghij')));
    });
  });
}

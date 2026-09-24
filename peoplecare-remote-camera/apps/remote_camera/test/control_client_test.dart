import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remote_camera/src/app/status_model.dart';
import 'package:remote_camera/src/control/control_client.dart';
import 'package:remote_camera/src/protocol/protocol.dart';

import 'support/fakes.dart';
import 'support/fixtures.dart';

void main() {
  group('control client', () {
    late List<FakeTransport> transports;
    late List<Map<String, String>> headers;
    late List<Uri> urls;
    late int probeStatus;

    ControlClient build({ControlHandlers handlers = const ControlHandlers(), bool failConnect = false}) {
      transports = [];
      headers = [];
      urls = [];
      probeStatus = 426;
      return ControlClient(
        serverUrl: Uri.parse('https://regia.example.com'),
        deviceToken: 'device-token-0123456789-abcdefghij',
        handlers: handlers,
        connector: (url, h) async {
          urls.add(url);
          headers.add(h);
          if (failConnect) throw Exception('connection refused');
          final t = FakeTransport();
          transports.add(t);
          return t;
        },
        httpClient: MockClient((request) async => http.Response('{}', probeStatus)),
        clock: () => 1790000000000,
      );
    }

    Map<String, Object?> welcome([String connId = 'conn_0011223344556677']) =>
        {...fixture('welcome.json'), 'connId': connId, 'serverTime': 1790000000000};

    test('authenticates with the device token in the header (never in the URL)', () {
      fakeAsync((async) {
        final client = build()..start();
        async.flushMicrotasks();
        expect(urls.single.toString(), 'wss://regia.example.com/ws/device');
        expect(headers.single['Authorization'], 'Bearer device-token-0123456789-abcdefghij');
        expect(urls.single.query, isEmpty);
        client.stop();
      });
    });

    test('goes connected on welcome and forwards validated commands with an immediate ACK', () {
      fakeAsync((async) {
        final statuses = <LinkState>[];
        final commands = <DeviceCommand>[];
        final client = build(handlers: ControlHandlers(onStatus: statuses.add, onCommand: commands.add))..start();
        async.flushMicrotasks();
        final t = transports.single;
        t.receive(welcome());
        async.flushMicrotasks();
        expect(client.connected, isTrue);
        expect(statuses.last, LinkState.connected);
        t.receive({...fixture('device_command.json'), 'sentAt': 1790000000000, 'expiresAt': 1790000015000});
        async.flushMicrotasks();
        expect(commands.single.command, 'set_zoom');
        final ack = t.sentOfType('ack').single;
        expect(ack['stage'], 'received');
        expect(ack['commandId'], commands.single.commandId);
        client.stop();
      });
    });

    test('refuses replayed and invalid commands with a failed ACK', () {
      fakeAsync((async) {
        final commands = <DeviceCommand>[];
        final client = build(handlers: ControlHandlers(onCommand: commands.add))..start();
        async.flushMicrotasks();
        final t = transports.single;
        t.receive(welcome());
        final command = {...fixture('device_command.json'), 'sentAt': 1790000000000, 'expiresAt': 1790000015000};
        t.receive(command);
        t.receive(command);
        t.receive({...command, 'commandId': 'bbbbbbbbbbbbbbbbbbbb', 'command': 'set_fps', 'value': 24, 'seq': 99});
        async.flushMicrotasks();
        expect(commands, hasLength(1));
        final acks = t.sentOfType('ack');
        expect(acks.where((a) => a['ok'] == false).map((a) => (a['error'] as Map)['code']), ['duplicate_command', 'invalid_value']);
        client.stop();
      });
    });

    test('reconnects with backoff after the socket drops', () {
      fakeAsync((async) {
        final statuses = <LinkState>[];
        final client = build(handlers: ControlHandlers(onStatus: statuses.add))..start();
        async.flushMicrotasks();
        transports.single.receive(welcome());
        async.flushMicrotasks();
        transports.single.serverClose(1006);
        async.flushMicrotasks();
        expect(statuses.last, LinkState.reconnecting);
        expect(transports, hasLength(1));
        async.elapse(const Duration(seconds: 1));
        expect(transports, hasLength(2));
        transports.last.receive(welcome('conn_second_000000'));
        async.flushMicrotasks();
        expect(statuses.last, LinkState.connected);
        client.stop();
      });
    });

    test('detects half-open connections with the heartbeat', () {
      fakeAsync((async) {
        var now = 1790000000000;
        transports = [];
        final client = ControlClient(
          serverUrl: Uri.parse('https://regia.example.com'),
          deviceToken: 'device-token-0123456789-abcdefghij',
          handlers: const ControlHandlers(),
          connector: (url, h) async {
            final t = FakeTransport();
            transports.add(t);
            return t;
          },
          httpClient: MockClient((request) async => http.Response('{}', 426)),
          clock: () => now,
        )..start();
        async.flushMicrotasks();
        transports.single.receive(welcome());
        async.flushMicrotasks();
        now += 15000;
        async.elapse(const Duration(seconds: 15));
        expect(transports.single.sentOfType('ping'), isNotEmpty);
        now += 45000;
        async.elapse(const Duration(seconds: 45));
        expect(transports.first.closeCode, 4000);
        async.elapse(const Duration(seconds: 2));
        expect(transports.length, greaterThanOrEqualTo(2));
        client.stop();
      });
    });

    test('stops and reports revocation on close code 4001', () {
      fakeAsync((async) {
        var revoked = 0;
        final client = build(handlers: ControlHandlers(onRevoked: () => revoked++))..start();
        async.flushMicrotasks();
        transports.single.receive(welcome());
        transports.single.serverClose(4001, 'revoked');
        async.flushMicrotasks();
        expect(revoked, 1);
        async.elapse(const Duration(minutes: 1));
        expect(transports, hasLength(1));
        client.stop();
      });
    });

    test('notifies the revocation once for message + close 4001, even if stopped inside the handler', () {
      fakeAsync((async) {
        var revoked = 0;
        late ControlClient client;
        client = build(handlers: ControlHandlers(onRevoked: () {
          revoked++;
          client.stop();
        }))
          ..start();
        async.flushMicrotasks();
        final t = transports.single..receive(welcome());
        async.flushMicrotasks();
        t.receive({'v': 1, 'type': 'revoked'});
        t.serverClose(4001, 'revoked');
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 1));
        expect(revoked, 1);
        expect(client.status, LinkState.error);
        expect(transports, hasLength(1));
      });
    });

    test('detects a revoked token when the upgrade fails (probe 401)', () {
      fakeAsync((async) {
        var unauthorized = 0;
        final client = build(handlers: ControlHandlers(onUnauthorized: () => unauthorized++), failConnect: true);
        probeStatus = 401;
        client.start();
        async.flushMicrotasks();
        expect(unauthorized, 1);
        expect(client.status, LinkState.error);
        client.stop();
      });
    });

    test('keeps retrying when the server is unreachable', () {
      fakeAsync((async) {
        final client = build(failConnect: true)..start();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        expect(urls.length, greaterThan(2));
        expect(client.status, LinkState.connecting);
        client.stop();
      });
    });

    test('maps http(s) to ws(s)', () {
      expect(ControlClient.deviceSocketUrl(Uri.parse('http://10.0.2.2:8787')).toString(), 'ws://10.0.2.2:8787/ws/device');
      expect(ControlClient.deviceSocketUrl(Uri.parse('https://a.example')).toString(), 'wss://a.example/ws/device');
    });
  });
}

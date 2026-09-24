import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remote_camera/src/pairing/credentials.dart';
import 'package:remote_camera/src/pairing/pairing_api.dart';
import 'package:remote_camera/src/pairing/pairing_controller.dart';

import 'support/fakes.dart';

void main() {
  group('server URL', () {
    test('normalizes and enforces HTTPS', () {
      expect(PairingApi.normalizeServerUrl('regia.example.com').toString(), 'https://regia.example.com');
      expect(PairingApi.normalizeServerUrl(' https://regia.example.com/path?x=1 ').toString(), 'https://regia.example.com');
      expect(() => PairingApi.normalizeServerUrl('http://regia.example.com'), throwsA(isA<PairingException>()));
      expect(PairingApi.normalizeServerUrl('http://10.0.2.2:8787', allowInsecure: true).toString(), 'http://10.0.2.2:8787');
      expect(() => PairingApi.normalizeServerUrl(''), throwsA(isA<PairingException>()));
    });

    test('QR payload format read by the Control Room', () {
      expect(pairingQrPayload('K7F2-9QXD', Uri.parse('https://regia.example.com')), 'PCRC:1:K7F2-9QXD:regia.example.com');
    });
  });

  group('pairing flow', () {
    late List<http.Request> requests;
    late int polls;

    Future<http.Response> Function(http.Request) handler({int pendingPolls = 2, bool expire = false}) {
      requests = [];
      polls = 0;
      return (request) async {
        requests.add(request);
        if (request.url.path == '/api/pair/start') {
          return http.Response(
            jsonEncode({
              'ok': true,
              'pairingId': 'pair_000000000000000000000001',
              'code': 'K7F2-9QXD',
              'pollToken': 'poll-token-0123456789',
              'expiresAt': DateTime.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch,
              'pollIntervalMs': 3000,
            }),
            200,
          );
        }
        if (request.url.path == '/api/pair/poll') {
          polls++;
          expect(request.headers['Authorization'], 'Bearer poll-token-0123456789');
          if (expire) return http.Response(jsonEncode({'ok': true, 'status': 'expired'}), 200);
          if (polls <= pendingPolls) return http.Response(jsonEncode({'ok': true, 'status': 'pending'}), 200);
          return http.Response(
            jsonEncode({
              'ok': true,
              'status': 'paired',
              'cameraId': 'cam_0a1b2c3d4e5f6a7b',
              'cameraName': 'CAM 01 - SALA',
              'slot': 1,
              'deviceToken': 'device-token-0123456789-abcdefghij',
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      };
    }

    MockClient server({int pendingPolls = 2, bool expire = false}) => MockClient(handler(pendingPolls: pendingPolls, expire: expire));

    test('requests a code, polls and stores the device token securely', () {
      fakeAsync((async) {
        final secrets = MemorySecretStore();
        final store = CredentialStore(secrets);
        StoredCredentials? paired;
        final client = server();
        final controller = PairingController(
          apiFactory: (uri) => PairingApi(uri, client: client),
          credentials: store,
          onPaired: (c) => paired = c,
        );
        controller.start(serverInput: 'regia.example.com', deviceName: 'Pixel', model: 'Google Pixel 9');
        async.flushMicrotasks();
        expect(controller.phase, PairingPhase.waiting);
        expect(controller.ticket?.code, 'K7F2-9QXD');
        final startBody = jsonDecode(requests.first.body) as Map;
        expect(startBody['deviceName'], 'Pixel');
        async.elapse(const Duration(seconds: 3));
        expect(controller.phase, PairingPhase.waiting);
        async.elapse(const Duration(seconds: 7));
        expect(controller.phase, PairingPhase.paired);
        expect(paired?.cameraName, 'CAM 01 - SALA');
        expect(paired?.serverUrl.toString(), 'https://regia.example.com');
        expect(secrets.values.values.single, contains('device-token-0123456789-abcdefghij'));
        controller.dispose();
      });
    });

    test('reports an expired code', () {
      fakeAsync((async) {
        final controller = PairingController(
          apiFactory: (uri) => PairingApi(uri, client: server(expire: true)),
          credentials: CredentialStore(MemorySecretStore()),
        );
        controller.start(serverInput: 'https://regia.example.com', deviceName: 'Pixel');
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 4));
        expect(controller.phase, PairingPhase.expired);
        controller.dispose();
      });
    });

    test('keeps polling through transient network errors', () {
      fakeAsync((async) {
        var failures = 0;
        final base = handler(pendingPolls: 0);
        final flaky = MockClient((request) async {
          if (request.url.path == '/api/pair/poll' && failures < 1) {
            failures++;
            throw http.ClientException('network down');
          }
          return base(request);
        });
        final controller = PairingController(
          apiFactory: (uri) => PairingApi(uri, client: flaky),
          credentials: CredentialStore(MemorySecretStore()),
        );
        controller.start(serverInput: 'https://regia.example.com', deviceName: 'Pixel');
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        expect(controller.warning, isNotNull);
        expect(controller.phase, PairingPhase.waiting);
        async.elapse(const Duration(seconds: 6));
        expect(controller.phase, PairingPhase.paired);
        controller.dispose();
      });
    });

    test('shows server errors (e.g. rate limit)', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({'ok': false, 'error': {'code': 'rate_limited', 'message': 'Troppe richieste di associazione'}}),
            429,
          ));
      final controller = PairingController(
        apiFactory: (uri) => PairingApi(uri, client: client),
        credentials: CredentialStore(MemorySecretStore()),
      );
      await controller.start(serverInput: 'https://regia.example.com', deviceName: 'Pixel');
      expect(controller.phase, PairingPhase.error);
      expect(controller.error, 'Troppe richieste di associazione');
      controller.dispose();
    });
  });

  group('credential store', () {
    test('keeps credentials and config only in the secret store', () async {
      final secrets = MemorySecretStore();
      final store = CredentialStore(secrets);
      await store.save(StoredCredentials(
        serverUrl: Uri.parse('https://regia.example.com'),
        cameraId: 'cam_1',
        cameraName: 'CAM 01',
        slot: 1,
        deviceToken: 'device-token-0123456789-abcdefghij',
      ));
      final loaded = await store.load();
      expect(loaded?.deviceToken, 'device-token-0123456789-abcdefghij');
      await store.clear();
      expect(await store.load(), isNull);
      expect(secrets.values, isEmpty);
    });

    test('ignores corrupted entries', () async {
      final secrets = MemorySecretStore()..values['pcrc.credentials.v1'] = '{not json';
      expect(await CredentialStore(secrets).load(), isNull);
    });
  });
}

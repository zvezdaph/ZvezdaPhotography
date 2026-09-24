import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remote_camera/src/app/app_controller.dart';
import 'package:remote_camera/src/app/settings_store.dart';
import 'package:remote_camera/src/app/status_model.dart';
import 'package:remote_camera/src/control/control_client.dart';
import 'package:remote_camera/src/engine/engine_bridge.dart';
import 'package:remote_camera/src/logging/app_logger.dart';
import 'package:remote_camera/src/models/engine_state.dart';
import 'package:remote_camera/src/pairing/credentials.dart';

import 'support/fakes.dart';
import 'support/fixtures.dart';

void main() {
  group('status model', () {
    test('LIVE only when the transport is really connected', () {
      expect(StatusModel.badge(const EngineState()), LiveBadge.offline);
      expect(StatusModel.badge(const EngineState(streamStatus: NativeStreamStatus.connecting)), LiveBadge.connecting);
      expect(StatusModel.badge(const EngineState(streamStatus: NativeStreamStatus.live)), LiveBadge.live);
      expect(StatusModel.badge(const EngineState(streamStatus: NativeStreamStatus.live, paused: true)), LiveBadge.paused);
      expect(StatusModel.badge(const EngineState(streamStatus: NativeStreamStatus.reconnecting)), LiveBadge.reconnecting);
      expect(StatusModel.badge(const EngineState(streamStatus: NativeStreamStatus.error)), LiveBadge.error);
    });

    test('maps the native state to the required link states', () {
      expect(StatusModel.streamLink(const EngineState(streamStatus: NativeStreamStatus.connecting)), LinkState.connecting);
      expect(StatusModel.streamLink(const EngineState(streamStatus: NativeStreamStatus.live)), LinkState.connected);
      expect(StatusModel.streamLink(const EngineState(streamStatus: NativeStreamStatus.reconnecting)), LinkState.reconnecting);
      expect(StatusModel.streamLink(const EngineState()), LinkState.disconnected);
      expect(StatusModel.streamLink(const EngineState(streamStatus: NativeStreamStatus.error)), LinkState.error);
    });

    test('traffic lights reflect real states', () {
      expect(StatusModel.cameraLight(const EngineState(cameraStatus: CameraStatus.ready)), Light.green);
      expect(StatusModel.cameraLight(const EngineState(cameraStatus: CameraStatus.error)), Light.red);
      const live = EngineState(streamStatus: NativeStreamStatus.live);
      expect(StatusModel.cloudflareLight(live, 'live'), Light.green);
      expect(StatusModel.cloudflareLight(live, 'offline'), Light.yellow);
      expect(StatusModel.cloudflareLight(live, 'error'), Light.red);
      expect(StatusModel.cloudflareLight(const EngineState(), null), Light.off);
      expect(StatusModel.controlLight(LinkState.connected), Light.green);
      expect(StatusModel.controlLight(LinkState.reconnecting), Light.yellow);
      expect(StatusModel.controlLight(LinkState.disconnected), Light.red);
    });
  });

  group('app controller', () {
    late FakeEngineBridge engine;
    late MemorySecretStore secrets;
    late List<FakeTransport> transports;
    late AppController app;

    Future<void> setUpPaired() async {
      engine = FakeEngineBridge();
      secrets = MemorySecretStore();
      transports = [];
      final store = CredentialStore(secrets);
      await store.save(StoredCredentials(
        serverUrl: Uri.parse('https://regia.example.com'),
        cameraId: 'cam_0a1b2c3d4e5f6a7b',
        cameraName: 'CAM 01 - SALA',
        slot: 1,
        deviceToken: 'device-token-0123456789-abcdefghij',
      ));
      app = AppController(
        engine: engine,
        credentialStore: store,
        settingsStore: MemorySettingsStore(),
        logger: AppLogger(),
        clock: () => 1790000000000,
        controlFactory: (credentials, handlers) => ControlClient(
          serverUrl: credentials.serverUrl,
          deviceToken: credentials.deviceToken,
          handlers: handlers,
          connector: (url, headers) async {
            final t = FakeTransport();
            transports.add(t);
            return t;
          },
          httpClient: MockClient((request) async => http.Response('{}', 426)),
          clock: () => 1790000000000,
        ),
      );
    }

    Map<String, Object?> command(String name, Object? value, int seq) => {
          'v': 1,
          'type': 'command',
          'commandId': 'cmd-${name.padRight(12, 'x')}-$seq',
          'seq': seq,
          'command': name,
          'value': value,
          'issuedAt': 1790000000000,
          'sentAt': 1790000000000,
          'expiresAt': 1790000015000,
          'issuedBy': 'Regista',
        };

    test('connects to the studio and introduces itself with capabilities and state', () {
      fakeAsync((async) {
        setUpPaired();
        async.flushMicrotasks();
        app.init();
        async.flushMicrotasks();
        app.prepareCamera();
        async.flushMicrotasks();
        expect(app.phase, AppPhase.paired);
        expect(app.cameraReady, isTrue);
        expect(app.preview?.textureId, 7);
        final t = transports.single;
        t.receive(fixture('welcome.json'));
        async.flushMicrotasks();
        final hello = t.sentOfType('hello').single;
        expect((hello['capabilities'] as Map)['resolutions'], ['720p', '1080p']);
        expect((hello['state'] as Map)['cameraStatus'], 'ready');
        expect(t.sentOfType('config_request'), hasLength(1));
        expect(t.sentOfType('telemetry'), isNotEmpty);
        app.dispose();
      });
    });

    test('executes a remote command and acknowledges the real result', () {
      fakeAsync((async) {
        setUpPaired();
        async.flushMicrotasks();
        app.init();
        async.flushMicrotasks();
        app.prepareCamera();
        async.flushMicrotasks();
        final t = transports.single..receive(fixture('welcome.json'));
        async.flushMicrotasks();
        t.receive(command('set_zoom', 2.5, 1));
        async.flushMicrotasks();
        expect(engine.calls, contains('setZoom:2.5'));
        final acks = t.sentOfType('ack');
        expect(acks.map((a) => a['stage']), ['received', 'completed']);
        expect(acks.last['ok'], isTrue);
        expect(acks.last['result'], {'zoom': 2.5});
        app.dispose();
      });
    });

    test('reports engine failures in the ACK (no fake success)', () {
      fakeAsync((async) {
        setUpPaired();
        async.flushMicrotasks();
        app.init();
        async.flushMicrotasks();
        app.prepareCamera();
        async.flushMicrotasks();
        final t = transports.single..receive(fixture('welcome.json'));
        async.flushMicrotasks();
        engine.failNext = EngineException('camera_off', 'La camera non è attiva');
        t.receive(command('set_exposure', 2, 1));
        async.flushMicrotasks();
        final completed = t.sentOfType('ack').last;
        expect(completed['ok'], isFalse);
        expect(completed['error'], {'code': 'camera_off', 'message': 'La camera non è attiva'});
        app.dispose();
      });
    });

    test('refuses unsupported hardware (torch on the front camera)', () {
      fakeAsync((async) {
        setUpPaired();
        async.flushMicrotasks();
        app.init();
        async.flushMicrotasks();
        app.prepareCamera();
        async.flushMicrotasks();
        engine.emitState({'facing': 'front'});
        async.flushMicrotasks();
        final t = transports.single..receive(fixture('welcome.json'));
        async.flushMicrotasks();
        t.receive(command('set_torch', true, 1));
        async.flushMicrotasks();
        expect(engine.calls.where((c) => c.startsWith('setTorch')), isEmpty);
        final completed = t.sentOfType('ack').last;
        expect((completed['error'] as Map)['code'], 'unsupported');
        app.dispose();
      });
    });

    test('starts SRT with the configuration received from the studio', () {
      fakeAsync((async) {
        setUpPaired();
        async.flushMicrotasks();
        app.init();
        async.flushMicrotasks();
        app.prepareCamera();
        async.flushMicrotasks();
        final t = transports.single..receive(fixture('welcome.json'));
        async.flushMicrotasks();
        t.receive(fixture('config.json'));
        async.flushMicrotasks();
        expect(app.streamingConfig?.protocol.name, 'srt');
        t.receive(command('start_stream', null, 1));
        async.flushMicrotasks();
        expect(engine.lastPrimary?.host, 'live.example.invalid');
        expect(t.sentOfType('ack').last['ok'], isTrue);
        // The configuration is cached in the secure store for offline starts.
        expect(secrets.values.keys, contains('pcrc.streaming_config.v1'));
        app.dispose();
      });
    });

    test('refuses START without a configuration', () {
      fakeAsync((async) {
        setUpPaired();
        async.flushMicrotasks();
        app.init();
        async.flushMicrotasks();
        app.prepareCamera();
        async.flushMicrotasks();
        Object? error;
        app.startStream(source: 'test').catchError((Object e) {
          error = e;
          return <String, Object?>{};
        });
        async.flushMicrotasks();
        expect(error, isA<EngineException>());
        expect((error! as EngineException).code, 'no_config');
        expect(engine.calls, isNot(contains('startStream')));
        app.dispose();
      });
    });

    test('pushes state changes to the studio', () {
      fakeAsync((async) {
        setUpPaired();
        async.flushMicrotasks();
        app.init();
        async.flushMicrotasks();
        app.prepareCamera();
        async.flushMicrotasks();
        final t = transports.single..receive(fixture('welcome.json'));
        async.flushMicrotasks();
        engine.emitState({'streamStatus': 'live'});
        async.elapse(const Duration(milliseconds: 200));
        final states = t.sentOfType('state');
        expect((states.last['state'] as Map)['streamStatus'], 'live');
        // telemetry every 2 s while live
        final before = t.sentOfType('telemetry').length;
        async.elapse(const Duration(seconds: 4));
        expect(t.sentOfType('telemetry').length - before, greaterThanOrEqualTo(2));
        app.dispose();
      });
    });

    test('forgets the studio when the device is revoked', () {
      fakeAsync((async) {
        setUpPaired();
        async.flushMicrotasks();
        app.init();
        async.flushMicrotasks();
        final t = transports.single..receive(fixture('welcome.json'));
        async.flushMicrotasks();
        t.receive({'v': 1, 'type': 'revoked'});
        t.serverClose(4001, 'revoked');
        async.flushMicrotasks();
        expect(app.phase, AppPhase.unpaired);
        expect(app.revokedMessage, contains('revocato'));
        expect(secrets.values, isEmpty);
        app.dispose();
      });
    });

    test('builds telemetry in the protocol shape', () {
      fakeAsync((async) {
        setUpPaired();
        async.flushMicrotasks();
        app.init();
        async.flushMicrotasks();
        engine.controller.add({'type': 'stats', 'bitrateKbps': 4870.0, 'uploadKbps': 5010.0, 'queuePercent': 2.0, 'fps': 30});
        engine.controller.add({
          'type': 'device',
          'batteryPercent': 81.0,
          'charging': true,
          'temperatureC': 36.4,
          'network': {'type': 'cellular', 'metered': true, 'validated': true, 'uplinkKbps': 18000},
        });
        engine.emitState({'streamStatus': 'live'});
        async.flushMicrotasks();
        final telemetry = app.buildTelemetry();
        final golden = (fixture('telemetry.json')['telemetry'] as Map).cast<String, Object?>();
        expect(telemetry.keys.toSet(), golden.keys.toSet());
        expect(telemetry['bitrateKbps'], 4870.0);
        expect((telemetry['battery'] as Map)['percent'], 81.0);
        expect((telemetry['network'] as Map)['type'], 'cellular');
        app.dispose();
      });
    });
  });
}

// Keeps the analyzer quiet about unawaited futures in fakeAsync zones.
void unawaitedTest(Future<void> f) => unawaited(f);

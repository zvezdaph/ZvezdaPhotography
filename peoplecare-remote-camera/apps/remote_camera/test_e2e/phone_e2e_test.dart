// Live end-to-end harness for the phone side, driven by tools/e2e/run_e2e.sh.
//
// It runs the REAL Dart layer of the app (PairingController, PairingApi over
// HTTP, AppController, ControlClient over a dart:io WebSocket, CommandGuard,
// CommandExecutor) against a running control plane (`wrangler dev`) while the
// Control Room is driven in Chromium. Only the native camera engine is
// replaced: _SimulatedEngine records the calls and reports the state changes
// a real engine would publish. No video is produced.
//
// Not part of `flutter test` (outside test/): it is skipped unless E2E_SERVER is set.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_camera/src/app/app_controller.dart';
import 'package:remote_camera/src/app/settings_store.dart';
import 'package:remote_camera/src/app/status_model.dart';
import 'package:remote_camera/src/logging/app_logger.dart';
import 'package:remote_camera/src/logging/diagnostics.dart';
import 'package:remote_camera/src/models/camera_streaming_config.dart';
import 'package:remote_camera/src/pairing/credentials.dart';
import 'package:remote_camera/src/pairing/pairing_api.dart';
import 'package:remote_camera/src/pairing/pairing_controller.dart';

import '../test/support/fakes.dart';

class _SimulatedEngine extends FakeEngineBridge {
  @override
  Future<Map<String, Object?>> startStream({
    required StreamEndpoint primary,
    StreamEndpoint? fallback,
    required bool autoFallback,
    required int srtLatencyMs,
  }) async {
    final result = await super.startStream(
      primary: primary,
      fallback: fallback,
      autoFallback: autoFallback,
      srtLatencyMs: srtLatencyMs,
    );
    emitState({'streamStatus': 'connecting', 'protocol': primary.protocol.name});
    Timer(const Duration(milliseconds: 500), () => emitState({'streamStatus': 'live'}));
    return result;
  }

  @override
  Future<void> stopStream() async {
    await super.stopStream();
    emitState({'streamStatus': 'idle', 'paused': false});
  }

  @override
  Future<void> pause() async {
    await super.pause();
    emitState({'paused': true});
  }

  @override
  Future<void> resume() async {
    await super.resume();
    emitState({'paused': false});
  }

  @override
  Future<Map<String, Object?>> zoomBy(double step) async {
    await super.zoomBy(step);
    final zoom = ((state['zoom'] as num).toDouble() + step).clamp(1.0, 8.0);
    emitState({'zoom': zoom});
    return {'zoom': zoom};
  }

  @override
  Future<Map<String, Object?>> setTorch(bool enabled) async {
    final result = await super.setTorch(enabled);
    emitState({'torch': enabled});
    return result;
  }

  @override
  Future<Map<String, Object?>> switchCamera(String facing) async {
    final result = await super.switchCamera(facing);
    emitState({'facing': facing, 'torch': false, 'zoom': 1.0});
    return result;
  }
}

Future<void> _waitFor(bool Function() condition, Duration timeout, String what) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('Timeout: $what');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  final env = Platform.environment;
  final server = env['E2E_SERVER'];

  test(
    'phone: pairing, control link and remote commands against a live control plane',
    () async {
      final codeFile = File(env['E2E_CODE_FILE']!);
      final doneFile = File(env['E2E_DONE_FILE']!);
      final store = CredentialStore(MemorySecretStore());
      final engine = _SimulatedEngine();
      final app = AppController(
        engine: engine,
        credentialStore: store,
        settingsStore: MemorySettingsStore(),
        logger: AppLogger(),
      );
      await app.init();
      await app.prepareCamera();
      expect(app.cameraReady, isTrue, reason: app.cameraError);

      final paired = Completer<StoredCredentials>();
      final pairing = PairingController(
        apiFactory: (uri) => PairingApi(uri, allowInsecure: true),
        credentials: store,
        allowInsecure: true,
        onPaired: paired.complete,
      );
      await pairing.start(serverInput: server!, deviceName: 'E2E Phone', model: 'E2E Harness', appVersion: '1.0.0');
      expect(pairing.phase, PairingPhase.waiting, reason: pairing.error);
      codeFile.writeAsStringSync(pairing.ticket!.code);
      stdout.writeln('[phone] pairing code ${pairing.ticket!.code}');

      final credentials = await paired.future.timeout(const Duration(minutes: 2));
      stdout.writeln('[phone] paired as "${credentials.cameraName}" (slot ${credentials.slot})');
      await app.onPaired(credentials);
      await _waitFor(() => app.controlStatus == LinkState.connected, const Duration(seconds: 20), 'control link');
      await _waitFor(() => app.streamingConfig != null, const Duration(seconds: 20), 'streaming configuration');
      stdout.writeln('[phone] connected, configuration: ${app.streamingConfig!.describeRedacted()}');

      await _waitFor(doneFile.existsSync, const Duration(minutes: 3), 'Control Room scenario');
      stdout.writeln('[phone] engine calls: ${engine.calls}');

      // Every command clicked in the Control Room reached the engine exactly as sent.
      expect(
        engine.calls,
        containsAllInOrder(<String>['startStream', 'zoomBy:0.5', 'setTorch:true', 'pause', 'resume', 'stopStream']),
      );
      // START used the SRT ingest credentials delivered by the Worker (from the mocked Stream API).
      expect(engine.lastPrimary!.protocol, StreamProtocol.srt);
      expect(engine.lastPrimary!.host, '127.0.0.1');
      expect(engine.lastPrimary!.streamId, isNotEmpty);
      expect(engine.lastPrimary!.passphrase, isNotEmpty);

      // The diagnostic report never contains the device token or the SRT secrets.
      final report = DiagnosticsReport.build(
        now: DateTime.now(),
        app: {'regia': credentials.serverUrl.host},
        device: const {},
        engine: const {},
        control: {'configurazione': app.streamingConfig!.describeRedacted()},
        logs: app.logger.recent(limit: 500),
      );
      expect(report, isNot(contains(credentials.deviceToken)));
      expect(report, isNot(contains(engine.lastPrimary!.passphrase!)));
      expect(report, isNot(contains(engine.lastPrimary!.streamId!)));

      pairing.dispose();
      app.dispose();
    },
    timeout: const Timeout(Duration(minutes: 6)),
    skip: server == null ? 'E2E_SERVER non impostato (usa tools/e2e/run_e2e.sh)' : false,
  );
}

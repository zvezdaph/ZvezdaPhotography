import 'dart:async';
import 'dart:convert';

import 'package:remote_camera/src/control/transport.dart';
import 'package:remote_camera/src/engine/engine_bridge.dart';
import 'package:remote_camera/src/models/camera_streaming_config.dart';
import 'package:remote_camera/src/models/video_settings.dart';
import 'package:remote_camera/src/pairing/credentials.dart';

import 'fixtures.dart';

class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// In-memory WebSocket used by ControlClient tests.
class FakeTransport implements ControlTransport {
  final StreamController<String> _incoming = StreamController<String>();
  final Completer<void> _done = Completer<void>();
  final List<Map<String, Object?>> sent = [];
  int? _closeCode;
  String? _closeReason;

  void receive(Map<String, Object?> message) => _incoming.add(jsonEncode(message));

  void serverClose(int code, [String reason = '']) {
    _closeCode = code;
    _closeReason = reason;
    _incoming.close();
    if (!_done.isCompleted) _done.complete();
  }

  List<Map<String, Object?>> sentOfType(String type) => sent.where((m) => m['type'] == type).toList();

  @override
  Stream<String> get messages => _incoming.stream;
  @override
  Future<void> get done => _done.future;
  @override
  int? get closeCode => _closeCode;
  @override
  String? get closeReason => _closeReason;
  @override
  void send(String data) => sent.add((jsonDecode(data) as Map).cast<String, Object?>());
  @override
  Future<void> close([int code = 1000, String reason = '']) async {
    if (_incoming.isClosed) return;
    serverClose(code, reason);
  }
}

/// Records calls; simulates only what the Dart layer needs (no fake video).
class FakeEngineBridge implements EngineBridge {
  final StreamController<Map<String, Object?>> controller = StreamController<Map<String, Object?>>.broadcast();
  final List<String> calls = [];
  Map<String, Object?> state = {
    'cameraStatus': 'ready',
    'streamStatus': 'idle',
    'facing': 'back',
    'zoom': 1.0,
    'resolution': '1080p',
    'width': 1920,
    'height': 1080,
    'fps': 30,
    'audioEnabled': true,
    'videoEnabled': true,
    'microphoneAvailable': true,
  };
  Map<String, Object?> capabilities = (fixture('hello.json')['capabilities'] as Map).cast<String, Object?>();
  EngineException? failNext;
  StreamEndpoint? lastPrimary;

  void emitState(Map<String, Object?> patch) {
    state = {...state, ...patch};
    controller.add({'type': 'state', ...state});
  }

  Future<T> _record<T>(String name, T value) async {
    calls.add(name);
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    return value;
  }

  @override
  Stream<Map<String, Object?>> get events => controller.stream;
  @override
  Future<Map<String, Object?>> deviceInfo() async =>
      {'manufacturer': 'Test', 'model': 'Phone', 'androidVersion': '16', 'sdkInt': 36, 'appVersion': '1.0.0', 'debug': true};
  @override
  Future<PermissionStatus> permissionStatus() async =>
      const PermissionStatus(camera: true, microphone: true, notifications: true);
  @override
  Future<PermissionStatus> requestPermissions() async =>
      const PermissionStatus(camera: true, microphone: true, notifications: true);
  @override
  Future<void> openAppSettings() => _record('openAppSettings', null);
  @override
  Future<Map<String, Object?>> initialize(VideoSettings settings) =>
      _record('initialize', {'capabilities': capabilities, 'state': state});
  @override
  Future<PreviewTexture> attachPreview(int width, int height) => _record('attachPreview', PreviewTexture(7, width, height));
  @override
  Future<void> detachPreview() => _record('detachPreview', null);
  @override
  Future<Map<String, Object?>> startStream({
    required StreamEndpoint primary,
    StreamEndpoint? fallback,
    required bool autoFallback,
    required int srtLatencyMs,
  }) {
    lastPrimary = primary;
    return _record('startStream', {'protocol': primary.protocol.name});
  }

  @override
  Future<Map<String, Object?>> startRawStream(String url) => _record('startRawStream', {'protocol': 'raw'});
  @override
  Future<void> stopStream() => _record('stopStream', null);
  @override
  Future<void> pause() => _record('pause', null);
  @override
  Future<void> resume() => _record('resume', null);
  @override
  Future<void> reconnect() => _record('reconnect', null);
  @override
  Future<void> restartStream() => _record('restartStream', null);
  @override
  Future<void> setVideoEnabled(bool enabled) => _record('setVideoEnabled:$enabled', null);
  @override
  Future<void> setAudioEnabled(bool enabled) => _record('setAudioEnabled:$enabled', null);
  @override
  Future<Map<String, Object?>> switchCamera(String facing) => _record('switchCamera:$facing', {'facing': facing});
  @override
  Future<Map<String, Object?>> setZoom(double zoom) => _record('setZoom:$zoom', {'zoom': zoom});
  @override
  Future<Map<String, Object?>> zoomBy(double step) => _record('zoomBy:$step', {'zoom': 1 + step});
  @override
  Future<Map<String, Object?>> setTorch(bool enabled) => _record('setTorch:$enabled', {'torch': enabled});
  @override
  Future<Map<String, Object?>> setAutoFocus(bool enabled) => _record('setAutoFocus:$enabled', {'autofocus': enabled});
  @override
  Future<Map<String, Object?>> focusAt(double x, double y) => _record('focusAt:$x,$y', {'x': x, 'y': y});
  @override
  Future<Map<String, Object?>> setExposure(int index) => _record('setExposure:$index', {'exposure': index});
  @override
  Future<Map<String, Object?>> applySettings(VideoSettings settings) =>
      _record('applySettings:${settings.resolution}/${settings.fps}/${settings.videoBitrateKbps}', {'restarted': false});
  @override
  Future<Map<String, Object?>> setBitrate(String mode, int? kbps) => _record('setBitrate:$mode/$kbps', {'mode': mode, 'kbps': kbps});
  @override
  Future<Map<String, Object?>> setRecording(bool enabled, String? label) =>
      _record('setRecording:$enabled', {'recording': enabled});
  @override
  Future<Map<String, Object?>> getState() => _record('getState', {'capabilities': capabilities, 'state': state});
  @override
  Future<void> setKeepScreenOn(bool enabled) => _record('setKeepScreenOn:$enabled', null);
  @override
  Future<void> setScreenBrightness(double value) => _record('setScreenBrightness:$value', null);
  @override
  Future<void> setOrientationLock(OrientationLock orientation) => _record('setOrientationLock:${orientation.name}', null);
  @override
  Future<void> shutdown() => _record('shutdown', null);
}

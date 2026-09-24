import 'dart:async';

import 'package:flutter/services.dart';

import '../models/camera_streaming_config.dart';
import '../models/video_settings.dart';

/// Error returned by the native engine (code + human readable message).
class EngineException implements Exception {
  EngineException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}

class PermissionStatus {
  const PermissionStatus({required this.camera, required this.microphone, required this.notifications});
  final bool camera;
  final bool microphone;
  final bool notifications;

  factory PermissionStatus.fromJson(Map<String, Object?> json) => PermissionStatus(
        camera: json['camera'] == true,
        microphone: json['microphone'] == true,
        notifications: json['notifications'] == true,
      );
}

class PreviewTexture {
  const PreviewTexture(this.textureId, this.width, this.height);
  final int textureId;
  final int width;
  final int height;
}

/// Contract of the native camera/streaming engine (Kotlin, RootEncoder).
abstract class EngineBridge {
  Stream<Map<String, Object?>> get events;
  Future<Map<String, Object?>> deviceInfo();
  Future<PermissionStatus> permissionStatus();
  Future<PermissionStatus> requestPermissions();
  Future<void> openAppSettings();
  Future<Map<String, Object?>> initialize(VideoSettings settings);
  Future<PreviewTexture> attachPreview(int width, int height);
  Future<void> detachPreview();
  Future<Map<String, Object?>> startStream({
    required StreamEndpoint primary,
    StreamEndpoint? fallback,
    required bool autoFallback,
    required int srtLatencyMs,
  });
  Future<Map<String, Object?>> startRawStream(String url);
  Future<void> stopStream();
  Future<void> pause();
  Future<void> resume();
  Future<void> reconnect();
  Future<void> restartStream();
  Future<void> setVideoEnabled(bool enabled);
  Future<void> setAudioEnabled(bool enabled);
  Future<Map<String, Object?>> switchCamera(String facing);
  Future<Map<String, Object?>> setZoom(double zoom);
  Future<Map<String, Object?>> zoomBy(double step);
  Future<Map<String, Object?>> setTorch(bool enabled);
  Future<Map<String, Object?>> setAutoFocus(bool enabled);
  Future<Map<String, Object?>> focusAt(double x, double y);
  Future<Map<String, Object?>> setExposure(int index);
  Future<Map<String, Object?>> applySettings(VideoSettings settings);
  Future<Map<String, Object?>> setBitrate(String mode, int? kbps);
  Future<Map<String, Object?>> setRecording(bool enabled, String? label);
  Future<Map<String, Object?>> getState();
  Future<void> setKeepScreenOn(bool enabled);
  Future<void> setScreenBrightness(double value);
  Future<void> setOrientationLock(OrientationLock orientation);
  Future<void> shutdown();
}

class MethodChannelEngineBridge implements EngineBridge {
  MethodChannelEngineBridge({MethodChannel? methods, EventChannel? events})
      : _methods = methods ?? const MethodChannel('tv.peoplecare.remotecamera/engine'),
        _events = events ?? const EventChannel('tv.peoplecare.remotecamera/events');

  final MethodChannel _methods;
  final EventChannel _events;
  Stream<Map<String, Object?>>? _stream;

  @override
  Stream<Map<String, Object?>> get events => _stream ??= _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => (event as Map).cast<String, Object?>())
      .asBroadcastStream();

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _methods.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw EngineException(e.code, e.message ?? e.code);
    } on MissingPluginException {
      throw EngineException('not_available', 'Motore nativo non disponibile');
    }
  }

  Future<Map<String, Object?>> _map(String method, [Map<String, Object?>? args]) async {
    final result = await _call<Map<Object?, Object?>>(method, args);
    return result?.cast<String, Object?>() ?? <String, Object?>{};
  }

  @override
  Future<Map<String, Object?>> deviceInfo() => _map('deviceInfo');

  @override
  Future<PermissionStatus> permissionStatus() async => PermissionStatus.fromJson(await _map('permissionStatus'));

  @override
  Future<PermissionStatus> requestPermissions() async => PermissionStatus.fromJson(await _map('requestPermissions'));

  @override
  Future<void> openAppSettings() => _call<void>('openAppSettings');

  @override
  Future<Map<String, Object?>> initialize(VideoSettings settings) =>
      _map('initialize', {'settings': settings.toJson()});

  @override
  Future<PreviewTexture> attachPreview(int width, int height) async {
    final result = await _map('attachPreview', {'width': width, 'height': height});
    return PreviewTexture(
      (result['textureId'] as num).toInt(),
      (result['width'] as num? ?? width).toInt(),
      (result['height'] as num? ?? height).toInt(),
    );
  }

  @override
  Future<void> detachPreview() => _call<void>('detachPreview');

  @override
  Future<Map<String, Object?>> startStream({
    required StreamEndpoint primary,
    StreamEndpoint? fallback,
    required bool autoFallback,
    required int srtLatencyMs,
  }) =>
      _map('startStream', {
        'primary': primary.toJson(),
        'fallback': fallback?.toJson(),
        'autoFallback': autoFallback,
        'srtLatencyMs': srtLatencyMs,
      });

  @override
  Future<Map<String, Object?>> startRawStream(String url) => _map('startStream', {
        'primary': {'protocol': 'raw', 'url': url},
        'fallback': null,
        'autoFallback': false,
        'srtLatencyMs': 500,
      });

  @override
  Future<void> stopStream() => _call<void>('stopStream');
  @override
  Future<void> pause() => _call<void>('pause');
  @override
  Future<void> resume() => _call<void>('resume');
  @override
  Future<void> reconnect() => _call<void>('reconnect');
  @override
  Future<void> restartStream() => _call<void>('restartStream');
  @override
  Future<void> setVideoEnabled(bool enabled) => _call<void>('setVideoEnabled', {'enabled': enabled});
  @override
  Future<void> setAudioEnabled(bool enabled) => _call<void>('setAudioEnabled', {'enabled': enabled});
  @override
  Future<Map<String, Object?>> switchCamera(String facing) => _map('switchCamera', {'facing': facing});
  @override
  Future<Map<String, Object?>> setZoom(double zoom) => _map('setZoom', {'zoom': zoom});
  @override
  Future<Map<String, Object?>> zoomBy(double step) => _map('zoomBy', {'step': step});
  @override
  Future<Map<String, Object?>> setTorch(bool enabled) => _map('setTorch', {'enabled': enabled});
  @override
  Future<Map<String, Object?>> setAutoFocus(bool enabled) => _map('setAutoFocus', {'enabled': enabled});
  @override
  Future<Map<String, Object?>> focusAt(double x, double y) => _map('focusAt', {'x': x, 'y': y});
  @override
  Future<Map<String, Object?>> setExposure(int index) => _map('setExposure', {'index': index});
  @override
  Future<Map<String, Object?>> applySettings(VideoSettings settings) =>
      _map('applySettings', {'settings': settings.toJson()});
  @override
  Future<Map<String, Object?>> setBitrate(String mode, int? kbps) => _map('setBitrate', {'mode': mode, 'kbps': kbps});
  @override
  Future<Map<String, Object?>> setRecording(bool enabled, String? label) =>
      _map('setRecording', {'enabled': enabled, 'label': label});
  @override
  Future<Map<String, Object?>> getState() => _map('getState');
  @override
  Future<void> setKeepScreenOn(bool enabled) => _call<void>('setKeepScreenOn', {'enabled': enabled});
  @override
  Future<void> setScreenBrightness(double value) => _call<void>('setScreenBrightness', {'value': value});
  @override
  Future<void> setOrientationLock(OrientationLock orientation) =>
      _call<void>('setOrientationLock', {'orientation': orientation.name});
  @override
  Future<void> shutdown() => _call<void>('shutdown');
}

/// Snapshot of the native engine state (events of type "state").
class EngineError {
  const EngineError({required this.code, required this.message, required this.ts});

  final String code;
  final String message;
  final int ts;

  factory EngineError.fromJson(Map<String, Object?> json) => EngineError(
        code: json['code'] is String ? json['code'] as String : 'error',
        message: json['message'] is String ? json['message'] as String : '',
        ts: json['ts'] is num ? (json['ts'] as num).toInt() : 0,
      );

  Map<String, Object?> toJson() => {'code': code, 'message': message, 'ts': ts};
}

/// Native streaming status.
enum NativeStreamStatus {
  idle,
  connecting,
  live,
  reconnecting,
  stopping,
  error;

  static NativeStreamStatus parse(Object? value) =>
      NativeStreamStatus.values.firstWhere((s) => s.name == value, orElse: () => NativeStreamStatus.idle);
}

enum CameraStatus {
  off,
  starting,
  ready,
  error;

  static CameraStatus parse(Object? value) =>
      CameraStatus.values.firstWhere((s) => s.name == value, orElse: () => CameraStatus.off);
}

class EngineState {
  const EngineState({
    this.cameraStatus = CameraStatus.off,
    this.streamStatus = NativeStreamStatus.idle,
    this.paused = false,
    this.facing = 'back',
    this.zoom = 1,
    this.torch = false,
    this.autofocus = false,
    this.exposure = 0,
    this.videoEnabled = true,
    this.audioEnabled = true,
    this.microphoneAvailable = false,
    this.recording = false,
    this.recordingFile,
    this.resolution = '1080p',
    this.width = 1920,
    this.height = 1080,
    this.fps = 30,
    this.bitrateMode = 'auto',
    this.targetBitrateKbps = 5000,
    this.currentVideoKbps = 0,
    this.audioBitrateKbps = 128,
    this.protocol = 'srt',
    this.fallbackActive = false,
    this.orientation = 'landscape',
    this.preview = false,
    this.reconnects = 0,
    this.reconnectAttempt = 0,
    this.sessionStartedAt,
    this.connectedAt,
    this.uptimeSec = 0,
    this.lastError,
    this.recentErrors = const [],
  });

  final CameraStatus cameraStatus;
  final NativeStreamStatus streamStatus;
  final bool paused;
  final String facing;
  final double zoom;
  final bool torch;
  final bool autofocus;
  final int exposure;
  final bool videoEnabled;
  final bool audioEnabled;
  final bool microphoneAvailable;
  final bool recording;
  final String? recordingFile;
  final String resolution;
  final int width;
  final int height;
  final int fps;
  final String bitrateMode;
  final int targetBitrateKbps;
  final int currentVideoKbps;
  final int audioBitrateKbps;
  final String protocol;
  final bool fallbackActive;
  final String orientation;
  final bool preview;
  final int reconnects;
  final int reconnectAttempt;
  final int? sessionStartedAt;
  final int? connectedAt;
  final int uptimeSec;
  final EngineError? lastError;
  final List<EngineError> recentErrors;

  bool get streaming =>
      streamStatus == NativeStreamStatus.connecting ||
      streamStatus == NativeStreamStatus.live ||
      streamStatus == NativeStreamStatus.reconnecting;

  static int _i(Object? v, int fallback) => v is num ? v.toInt() : fallback;

  factory EngineState.fromJson(Map<String, Object?> json) {
    final lastError = json['lastError'];
    final recent = json['recentErrors'];
    return EngineState(
      cameraStatus: CameraStatus.parse(json['cameraStatus']),
      streamStatus: NativeStreamStatus.parse(json['streamStatus']),
      paused: json['paused'] == true,
      facing: json['facing'] == 'front' ? 'front' : 'back',
      zoom: json['zoom'] is num ? (json['zoom'] as num).toDouble() : 1,
      torch: json['torch'] == true,
      autofocus: json['autofocus'] == true,
      exposure: _i(json['exposure'], 0),
      videoEnabled: json['videoEnabled'] != false,
      audioEnabled: json['audioEnabled'] != false,
      microphoneAvailable: json['microphoneAvailable'] == true,
      recording: json['recording'] == true,
      recordingFile: json['recordingFile'] is String ? json['recordingFile'] as String : null,
      resolution: json['resolution'] == '720p' ? '720p' : '1080p',
      width: _i(json['width'], 1920),
      height: _i(json['height'], 1080),
      fps: _i(json['fps'], 30),
      bitrateMode: json['bitrateMode'] == 'manual' ? 'manual' : 'auto',
      targetBitrateKbps: _i(json['targetBitrateKbps'], 5000),
      currentVideoKbps: _i(json['currentVideoKbps'], 0),
      audioBitrateKbps: _i(json['audioBitrateKbps'], 128),
      protocol: json['protocol'] == 'rtmps' ? 'rtmps' : 'srt',
      fallbackActive: json['fallbackActive'] == true,
      orientation: json['orientation'] == 'portrait' ? 'portrait' : 'landscape',
      preview: json['preview'] == true,
      reconnects: _i(json['reconnects'], 0),
      reconnectAttempt: _i(json['reconnectAttempt'], 0),
      sessionStartedAt: json['sessionStartedAt'] is num ? (json['sessionStartedAt'] as num).toInt() : null,
      connectedAt: json['connectedAt'] is num ? (json['connectedAt'] as num).toInt() : null,
      uptimeSec: _i(json['uptimeSec'], 0),
      lastError: lastError is Map ? EngineError.fromJson(lastError.cast<String, Object?>()) : null,
      recentErrors: recent is List
          ? recent.whereType<Map<Object?, Object?>>().map((e) => EngineError.fromJson(e.cast<String, Object?>())).toList()
          : const [],
    );
  }
}

/// Per-second streaming statistics (events of type "stats").
class StreamStats {
  const StreamStats({
    this.bitrateKbps = 0,
    this.uploadKbps = 0,
    this.queuePercent = 0,
    this.fps = 0,
    this.throughput = 'unknown',
    this.targetVideoKbps = 0,
  });

  final double bitrateKbps;
  final double uploadKbps;
  final double queuePercent;
  final int fps;
  final String throughput;
  final int targetVideoKbps;

  factory StreamStats.fromJson(Map<String, Object?> json) => StreamStats(
        bitrateKbps: json['bitrateKbps'] is num ? (json['bitrateKbps'] as num).toDouble() : 0,
        uploadKbps: json['uploadKbps'] is num ? (json['uploadKbps'] as num).toDouble() : 0,
        queuePercent: json['queuePercent'] is num ? (json['queuePercent'] as num).toDouble() : 0,
        fps: json['fps'] is num ? (json['fps'] as num).toInt() : 0,
        throughput: json['throughput'] is String ? json['throughput'] as String : 'unknown',
        targetVideoKbps: json['targetVideoKbps'] is num ? (json['targetVideoKbps'] as num).toInt() : 0,
      );
}

class NetworkInfo {
  const NetworkInfo({this.type = 'none', this.metered = false, this.validated = false, this.uplinkKbps});

  final String type;
  final bool metered;
  final bool validated;
  final int? uplinkKbps;

  factory NetworkInfo.fromJson(Map<String, Object?> json) => NetworkInfo(
        type: json['type'] is String ? json['type'] as String : 'other',
        metered: json['metered'] == true,
        validated: json['validated'] == true,
        uplinkKbps: json['uplinkKbps'] is num ? (json['uplinkKbps'] as num).toInt() : null,
      );

  String get label => switch (type) {
        'wifi' => 'Wi-Fi',
        'cellular' => 'Rete mobile',
        'ethernet' => 'Ethernet',
        'vpn' => 'VPN',
        'none' => 'Nessuna rete',
        _ => 'Altra rete',
      };

  Map<String, Object?> toJson() => {'type': type, 'metered': metered, 'validated': validated, 'uplinkKbps': uplinkKbps};
}

/// Battery, temperature and storage (events of type "device").
class DeviceStatus {
  const DeviceStatus({
    this.batteryPercent,
    this.charging = false,
    this.temperatureC,
    this.thermal,
    this.storageFreeBytes,
    this.network = const NetworkInfo(),
  });

  final double? batteryPercent;
  final bool charging;
  final double? temperatureC;
  final String? thermal;
  final int? storageFreeBytes;
  final NetworkInfo network;

  factory DeviceStatus.fromJson(Map<String, Object?> json) => DeviceStatus(
        batteryPercent: json['batteryPercent'] is num ? (json['batteryPercent'] as num).toDouble() : null,
        charging: json['charging'] == true,
        temperatureC: json['temperatureC'] is num ? (json['temperatureC'] as num).toDouble() : null,
        thermal: json['thermal'] is String ? json['thermal'] as String : null,
        storageFreeBytes: json['storageFreeBytes'] is num ? (json['storageFreeBytes'] as num).toInt() : null,
        network: json['network'] is Map
            ? NetworkInfo.fromJson((json['network'] as Map).cast<String, Object?>())
            : const NetworkInfo(),
      );

  DeviceStatus withNetwork(NetworkInfo network) => DeviceStatus(
        batteryPercent: batteryPercent,
        charging: charging,
        temperatureC: temperatureC,
        thermal: thermal,
        storageFreeBytes: storageFreeBytes,
        network: network,
      );
}

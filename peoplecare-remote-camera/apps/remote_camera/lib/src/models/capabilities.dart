/// Real hardware capabilities reported by the native engine (Camera2 +
/// MediaCodec). The UI and the control room only enable what is listed here.
class FacingCapabilities {
  const FacingCapabilities({
    required this.available,
    required this.zoomSupported,
    required this.zoomMin,
    required this.zoomMax,
    required this.torch,
    required this.autofocus,
    required this.focusPoint,
    required this.exposureSupported,
    required this.exposureMin,
    required this.exposureMax,
    required this.exposureStep,
    required this.fps,
  });

  final bool available;
  final bool zoomSupported;
  final double zoomMin;
  final double zoomMax;
  final bool torch;
  final bool autofocus;
  final bool focusPoint;
  final bool exposureSupported;
  final int exposureMin;
  final int exposureMax;
  final double exposureStep;

  /// Frame rates supported for each resolution label ("720p", "1080p").
  final Map<String, List<int>> fps;

  static double _d(Object? v, double fallback) => v is num ? v.toDouble() : fallback;
  static int _i(Object? v, int fallback) => v is num ? v.toInt() : fallback;

  factory FacingCapabilities.fromJson(Map<String, Object?> json) {
    final zoom = json['zoom'] is Map ? (json['zoom'] as Map).cast<String, Object?>() : const <String, Object?>{};
    final exposure =
        json['exposure'] is Map ? (json['exposure'] as Map).cast<String, Object?>() : const <String, Object?>{};
    final fps = <String, List<int>>{};
    final fpsJson = json['fps'];
    if (fpsJson is Map) {
      for (final entry in fpsJson.entries) {
        final list = entry.value;
        if (entry.key is String && list is List) {
          fps[entry.key as String] = list.whereType<num>().map((e) => e.toInt()).toList();
        }
      }
    }
    return FacingCapabilities(
      available: json['available'] == true,
      zoomSupported: zoom['supported'] == true,
      zoomMin: _d(zoom['min'], 1),
      zoomMax: _d(zoom['max'], 1),
      torch: json['torch'] == true,
      autofocus: json['autofocus'] == true,
      focusPoint: json['focusPoint'] == true,
      exposureSupported: exposure['supported'] == true,
      exposureMin: _i(exposure['min'], 0),
      exposureMax: _i(exposure['max'], 0),
      exposureStep: _d(exposure['step'], 0),
      fps: fps,
    );
  }

  Map<String, Object?> toJson() => {
        'available': available,
        'zoom': {'supported': zoomSupported, 'min': zoomMin, 'max': zoomMax},
        'torch': torch,
        'autofocus': autofocus,
        'focusPoint': focusPoint,
        'exposure': {'supported': exposureSupported, 'min': exposureMin, 'max': exposureMax, 'step': exposureStep},
        'fps': fps,
      };
}

class DeviceCapabilities {
  const DeviceCapabilities({
    required this.facings,
    required this.resolutions,
    required this.recording,
    required this.protocols,
    required this.maxBitrateKbps,
    required this.microphone,
  });

  static const empty = DeviceCapabilities(
    facings: {},
    resolutions: [],
    recording: false,
    protocols: ['srt', 'rtmps'],
    maxBitrateKbps: 12000,
    microphone: false,
  );

  final Map<String, FacingCapabilities> facings;
  final List<String> resolutions;
  final bool recording;
  final List<String> protocols;
  final int maxBitrateKbps;
  final bool microphone;

  FacingCapabilities? facing(String name) => facings[name];

  bool supportsFps(String facingName, String resolution, int fps) =>
      facings[facingName]?.fps[resolution]?.contains(fps) ?? false;

  factory DeviceCapabilities.fromJson(Map<String, Object?> json) {
    final facings = <String, FacingCapabilities>{};
    final raw = json['facings'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.key is String && entry.value is Map) {
          facings[entry.key as String] = FacingCapabilities.fromJson((entry.value as Map).cast<String, Object?>());
        }
      }
    }
    return DeviceCapabilities(
      facings: facings,
      resolutions: (json['resolutions'] is List ? json['resolutions'] as List : const []).whereType<String>().toList(),
      recording: json['recording'] == true,
      protocols: (json['protocols'] is List ? json['protocols'] as List : const ['srt', 'rtmps']).whereType<String>().toList(),
      maxBitrateKbps: json['maxBitrateKbps'] is num ? (json['maxBitrateKbps'] as num).toInt() : 12000,
      microphone: json['microphone'] == true,
    );
  }

  /// Shape expected by the control plane (`hello.capabilities`).
  Map<String, Object?> toProtocolJson() => {
        'facings': facings.map((key, value) => MapEntry(key, value.toJson())),
        'resolutions': resolutions,
        'recording': recording,
        'protocols': protocols,
        'maxBitrateKbps': maxBitrateKbps.clamp(500, 12000),
      };
}

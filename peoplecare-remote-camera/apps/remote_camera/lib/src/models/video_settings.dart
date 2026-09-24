import 'capabilities.dart';

enum BitrateMode {
  auto,
  manual;

  static BitrateMode parse(Object? value) => value == 'manual' ? BitrateMode.manual : BitrateMode.auto;
}

enum OrientationLock {
  landscape,
  portrait;

  static OrientationLock parse(Object? value) => value == 'portrait' ? OrientationLock.portrait : OrientationLock.landscape;
}

/// Presets requested for the project. Values are applied only if the
/// hardware supports them (see [VideoSettings.constrainedTo]).
enum VideoPreset {
  low('LOW', '720p', 25, 2000),
  standard('STANDARD', '1080p', 30, 5000),
  high('HIGH', '1080p', 30, 7000);

  const VideoPreset(this.label, this.resolution, this.fps, this.videoBitrateKbps);

  final String label;
  final String resolution;
  final int fps;
  final int videoBitrateKbps;

  static VideoPreset? parse(Object? value) => switch (value) {
        'low' => VideoPreset.low,
        'standard' => VideoPreset.standard,
        'high' => VideoPreset.high,
        _ => null,
      };
}

class VideoSettings {
  const VideoSettings({
    this.resolution = '1080p',
    this.fps = 30,
    this.videoBitrateKbps = 5000,
    this.audioBitrateKbps = 128,
    this.bitrateMode = BitrateMode.auto,
    this.keyframeIntervalSec = 2,
    this.orientation = OrientationLock.landscape,
  });

  static const minBitrateKbps = 500;
  static const maxBitrateKbps = 12000;

  final String resolution;
  final int fps;
  final int videoBitrateKbps;
  final int audioBitrateKbps;
  final BitrateMode bitrateMode;
  final int keyframeIntervalSec;
  final OrientationLock orientation;

  int get width => resolution == '720p' ? 1280 : 1920;
  int get height => resolution == '720p' ? 720 : 1080;

  /// Encoded frame size (portrait swaps width/height).
  (int, int) get frameSize => orientation == OrientationLock.portrait ? (height, width) : (width, height);

  VideoSettings copyWith({
    String? resolution,
    int? fps,
    int? videoBitrateKbps,
    int? audioBitrateKbps,
    BitrateMode? bitrateMode,
    int? keyframeIntervalSec,
    OrientationLock? orientation,
  }) =>
      VideoSettings(
        resolution: resolution ?? this.resolution,
        fps: fps ?? this.fps,
        videoBitrateKbps: videoBitrateKbps ?? this.videoBitrateKbps,
        audioBitrateKbps: audioBitrateKbps ?? this.audioBitrateKbps,
        bitrateMode: bitrateMode ?? this.bitrateMode,
        keyframeIntervalSec: keyframeIntervalSec ?? this.keyframeIntervalSec,
        orientation: orientation ?? this.orientation,
      );

  VideoSettings applyPreset(VideoPreset preset) => copyWith(
        resolution: preset.resolution,
        fps: preset.fps,
        videoBitrateKbps: preset.videoBitrateKbps,
      );

  /// Returns settings that the device really supports: unsupported
  /// resolution or frame rate are replaced with the closest supported value,
  /// the bitrate is clamped to Cloudflare's recommended range.
  VideoSettings constrainedTo(DeviceCapabilities caps, String facing) {
    final facingCaps = caps.facing(facing);
    var result = this;
    if (caps.resolutions.isNotEmpty && !caps.resolutions.contains(result.resolution)) {
      result = result.copyWith(resolution: caps.resolutions.last);
    }
    final supportedFps = facingCaps?.fps[result.resolution] ?? const <int>[];
    if (supportedFps.isNotEmpty && !supportedFps.contains(result.fps)) {
      final lower = supportedFps.where((f) => f <= result.fps).toList()..sort();
      result = result.copyWith(fps: lower.isNotEmpty ? lower.last : supportedFps.first);
    }
    final maxKbps = caps.maxBitrateKbps.clamp(minBitrateKbps, maxBitrateKbps);
    return result.copyWith(videoBitrateKbps: result.videoBitrateKbps.clamp(minBitrateKbps, maxKbps));
  }

  Map<String, Object?> toJson() => {
        'resolution': resolution,
        'fps': fps,
        'videoBitrateKbps': videoBitrateKbps,
        'audioBitrateKbps': audioBitrateKbps,
        'bitrateMode': bitrateMode.name,
        'keyframeIntervalSec': keyframeIntervalSec,
        'orientation': orientation.name,
      };

  factory VideoSettings.fromJson(Map<String, Object?> json) {
    final fps = json['fps'] is num ? (json['fps'] as num).toInt() : 30;
    return VideoSettings(
      resolution: json['resolution'] == '720p' ? '720p' : '1080p',
      fps: const [25, 30, 50, 60].contains(fps) ? fps : 30,
      videoBitrateKbps: (json['videoBitrateKbps'] is num ? (json['videoBitrateKbps'] as num).toInt() : 5000)
          .clamp(minBitrateKbps, maxBitrateKbps),
      audioBitrateKbps:
          (json['audioBitrateKbps'] is num ? (json['audioBitrateKbps'] as num).toInt() : 128).clamp(64, 320),
      bitrateMode: BitrateMode.parse(json['bitrateMode']),
      keyframeIntervalSec:
          (json['keyframeIntervalSec'] is num ? (json['keyframeIntervalSec'] as num).toInt() : 2).clamp(1, 8),
      orientation: OrientationLock.parse(json['orientation']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VideoSettings &&
      other.resolution == resolution &&
      other.fps == fps &&
      other.videoBitrateKbps == videoBitrateKbps &&
      other.audioBitrateKbps == audioBitrateKbps &&
      other.bitrateMode == bitrateMode &&
      other.keyframeIntervalSec == keyframeIntervalSec &&
      other.orientation == orientation;

  @override
  int get hashCode =>
      Object.hash(resolution, fps, videoBitrateKbps, audioBitrateKbps, bitrateMode, keyframeIntervalSec, orientation);
}

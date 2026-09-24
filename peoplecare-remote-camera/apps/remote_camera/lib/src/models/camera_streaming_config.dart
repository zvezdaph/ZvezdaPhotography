/// Streaming configuration received (authenticated) from the control plane.
///
/// It mirrors `CameraStreamingConfig` in cloudflare/worker/src/shared/protocol.ts.
/// SRT is the primary protocol, RTMPS the optional fallback.
library;

enum StreamProtocol {
  srt,
  rtmps;

  static StreamProtocol? parse(Object? value) => switch (value) {
        'srt' => StreamProtocol.srt,
        'rtmps' => StreamProtocol.rtmps,
        _ => null,
      };
}

class ConfigFormatException implements Exception {
  ConfigFormatException(this.message);
  final String message;
  @override
  String toString() => 'ConfigFormatException: $message';
}

/// One ingest endpoint of a Cloudflare Stream live input.
class StreamEndpoint {
  const StreamEndpoint({
    required this.protocol,
    required this.url,
    required this.host,
    required this.port,
    this.streamId,
    this.passphrase,
    this.streamKey,
  });

  final StreamProtocol protocol;
  final String url;
  final String host;
  final int port;
  final String? streamId;
  final String? passphrase;
  final String? streamKey;

  static StreamEndpoint fromJson(Map<String, Object?> json) {
    final protocol = StreamProtocol.parse(json['protocol']);
    if (protocol == null) throw ConfigFormatException('protocol must be srt or rtmps');
    final url = json['url'];
    if (url is! String || url.isEmpty) throw ConfigFormatException('url missing');
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) throw ConfigFormatException('invalid url');
    final expectedScheme = protocol == StreamProtocol.srt ? 'srt' : 'rtmps';
    if (uri.scheme.toLowerCase() != expectedScheme) {
      throw ConfigFormatException('url scheme must be $expectedScheme');
    }
    final host = json['host'] is String && (json['host'] as String).isNotEmpty ? json['host'] as String : uri.host;
    final portValue = json['port'];
    final port = portValue is num ? portValue.toInt() : (uri.hasPort ? uri.port : (protocol == StreamProtocol.rtmps ? 443 : 0));
    if (port <= 0 || port > 65535) throw ConfigFormatException('invalid port');
    final streamId = json['streamId'] is String ? json['streamId'] as String : null;
    final passphrase = json['passphrase'] is String ? json['passphrase'] as String : null;
    final streamKey = json['streamKey'] is String ? json['streamKey'] as String : null;
    if (protocol == StreamProtocol.srt) {
      if (streamId == null || streamId.isEmpty) throw ConfigFormatException('SRT streamId missing');
      if (passphrase != null && passphrase.isNotEmpty && (passphrase.length < 10 || passphrase.length > 79)) {
        throw ConfigFormatException('SRT passphrase must be 10..79 characters');
      }
    } else if (streamKey == null || streamKey.isEmpty) {
      throw ConfigFormatException('RTMPS streamKey missing');
    }
    return StreamEndpoint(
      protocol: protocol,
      url: url,
      host: host,
      port: port,
      streamId: streamId,
      passphrase: passphrase,
      streamKey: streamKey,
    );
  }

  Map<String, Object?> toJson() => {
        'protocol': protocol.name,
        'url': url,
        'host': host,
        'port': port,
        if (streamId != null) 'streamId': streamId,
        if (passphrase != null) 'passphrase': passphrase,
        if (streamKey != null) 'streamKey': streamKey,
      };

  /// Only what is safe to show in logs and diagnostics.
  String describeRedacted() => '${protocol.name.toUpperCase()} $host:$port';
}

class CameraStreamingConfig {
  const CameraStreamingConfig({
    required this.cameraId,
    required this.cameraName,
    required this.primary,
    required this.fallback,
    required this.resolution,
    required this.fps,
    required this.videoBitrateKbps,
    required this.audioBitrateKbps,
    required this.bitrateMode,
    required this.keyframeIntervalSec,
    required this.srtLatencyMs,
    required this.issuedAt,
  });

  final String cameraId;
  final String cameraName;
  final StreamEndpoint primary;
  final StreamEndpoint? fallback;
  final String resolution;
  final int fps;
  final int videoBitrateKbps;
  final int audioBitrateKbps;
  final String bitrateMode;
  final int keyframeIntervalSec;
  final int srtLatencyMs;
  final int issuedAt;

  StreamProtocol get protocol => primary.protocol;
  String get url => primary.url;
  String get host => primary.host;
  int get port => primary.port;
  String? get streamId => primary.streamId;
  String? get passphrase => primary.passphrase;

  static int _int(Object? value, int fallback, int min, int max) {
    if (value is num) return value.toInt().clamp(min, max);
    return fallback;
  }

  static CameraStreamingConfig fromJson(Map<String, Object?> json) {
    final cameraId = json['cameraId'];
    if (cameraId is! String || cameraId.isEmpty) throw ConfigFormatException('cameraId missing');
    final primary = StreamEndpoint.fromJson(json);
    StreamEndpoint? fallback;
    final rawFallback = json['fallback'];
    if (rawFallback is Map) {
      fallback = StreamEndpoint.fromJson(rawFallback.cast<String, Object?>());
    }
    final resolution = json['resolution'] == '720p' ? '720p' : '1080p';
    final fps = _int(json['fps'], 30, 1, 60);
    return CameraStreamingConfig(
      cameraId: cameraId,
      cameraName: json['cameraName'] is String ? json['cameraName'] as String : cameraId,
      primary: primary,
      fallback: fallback,
      resolution: resolution,
      fps: const [25, 30, 50, 60].contains(fps) ? fps : 30,
      videoBitrateKbps: _int(json['videoBitrateKbps'], 5000, 500, 12000),
      audioBitrateKbps: _int(json['audioBitrateKbps'], 128, 64, 320),
      bitrateMode: json['bitrateMode'] == 'manual' ? 'manual' : 'auto',
      keyframeIntervalSec: _int(json['keyframeIntervalSec'], 2, 1, 8),
      srtLatencyMs: _int(json['srtLatencyMs'], 500, 80, 8000),
      issuedAt: _int(json['issuedAt'], 0, 0, 1 << 53),
    );
  }

  Map<String, Object?> toJson() => {
        'cameraId': cameraId,
        'cameraName': cameraName,
        ...primary.toJson(),
        'fallback': fallback?.toJson(),
        'resolution': resolution,
        'fps': fps,
        'videoBitrateKbps': videoBitrateKbps,
        'audioBitrateKbps': audioBitrateKbps,
        'bitrateMode': bitrateMode,
        'keyframeIntervalSec': keyframeIntervalSec,
        'srtLatencyMs': srtLatencyMs,
        'issuedAt': issuedAt,
      };

  CameraStreamingConfig withName(String name) => CameraStreamingConfig(
        cameraId: cameraId,
        cameraName: name,
        primary: primary,
        fallback: fallback,
        resolution: resolution,
        fps: fps,
        videoBitrateKbps: videoBitrateKbps,
        audioBitrateKbps: audioBitrateKbps,
        bitrateMode: bitrateMode,
        keyframeIntervalSec: keyframeIntervalSec,
        srtLatencyMs: srtLatencyMs,
        issuedAt: issuedAt,
      );

  String describeRedacted() =>
      '${primary.describeRedacted()}${fallback != null ? ' (fallback ${fallback!.describeRedacted()})' : ''}';
}

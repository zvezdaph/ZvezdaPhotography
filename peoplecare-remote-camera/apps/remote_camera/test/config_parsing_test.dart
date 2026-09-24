import 'package:flutter_test/flutter_test.dart';
import 'package:remote_camera/src/models/camera_streaming_config.dart';
import 'package:remote_camera/src/models/capabilities.dart';
import 'package:remote_camera/src/models/video_settings.dart';

import 'support/fixtures.dart';

void main() {
  final golden = (fixture('config.json')['config'] as Map).cast<String, Object?>();

  group('CameraStreamingConfig', () {
    test('parses the configuration delivered by the control plane', () {
      final config = CameraStreamingConfig.fromJson(golden);
      expect(config.cameraId, 'cam_0a1b2c3d4e5f6a7b');
      expect(config.cameraName, 'CAM 01 - SALA');
      expect(config.protocol, StreamProtocol.srt);
      expect(config.host, 'live.example.invalid');
      expect(config.port, 778);
      expect(config.streamId, '0123456789abcdef0123456789abcdef');
      expect(config.passphrase, 'fixture-passphrase-not-a-secret');
      expect(config.fallback?.protocol, StreamProtocol.rtmps);
      expect(config.fallback?.port, 443);
      expect(config.resolution, '1080p');
      expect(config.fps, 30);
      expect(config.videoBitrateKbps, 5000);
      expect(config.audioBitrateKbps, 128);
      expect(config.srtLatencyMs, 500);
    });

    test('round-trips through JSON (secure storage cache)', () {
      final config = CameraStreamingConfig.fromJson(golden);
      final again = CameraStreamingConfig.fromJson(config.toJson());
      expect(again.toJson(), config.toJson());
    });

    test('never prints secrets in its description', () {
      final text = CameraStreamingConfig.fromJson(golden).describeRedacted();
      expect(text, contains('SRT live.example.invalid:778'));
      expect(text, isNot(contains('fixture-passphrase')));
      expect(text, isNot(contains('fixture-stream-key')));
      expect(text, isNot(contains('0123456789abcdef')));
    });

    test('rejects malformed endpoints', () {
      expect(() => CameraStreamingConfig.fromJson({...golden, 'url': 'rtmp://x:1'}), throwsA(isA<ConfigFormatException>()));
      expect(() => CameraStreamingConfig.fromJson({...golden, 'streamId': ''}), throwsA(isA<ConfigFormatException>()));
      expect(() => CameraStreamingConfig.fromJson({...golden, 'passphrase': 'short'}), throwsA(isA<ConfigFormatException>()));
      expect(() => CameraStreamingConfig.fromJson({...golden, 'port': 0}), throwsA(isA<ConfigFormatException>()));
      expect(() => CameraStreamingConfig.fromJson({...golden, 'cameraId': null}), throwsA(isA<ConfigFormatException>()));
      final noKey = {...golden, 'fallback': {'protocol': 'rtmps', 'url': 'rtmps://live.example.invalid:443/live/'}};
      expect(() => CameraStreamingConfig.fromJson(noKey), throwsA(isA<ConfigFormatException>()));
    });

    test('accepts an RTMPS-only live input', () {
      final config = CameraStreamingConfig.fromJson({
        'cameraId': 'cam_1',
        'protocol': 'rtmps',
        'url': 'rtmps://live.example.invalid/live/',
        'streamKey': 'key',
      });
      expect(config.port, 443);
      expect(config.fallback, isNull);
    });

    test('clamps numeric values to safe ranges', () {
      final config = CameraStreamingConfig.fromJson({...golden, 'videoBitrateKbps': 99999, 'fps': 24, 'srtLatencyMs': 1});
      expect(config.videoBitrateKbps, 12000);
      expect(config.fps, 30);
      expect(config.srtLatencyMs, 80);
    });
  });

  group('VideoSettings', () {
    final caps = DeviceCapabilities.fromJson((fixture('hello.json')['capabilities'] as Map).cast<String, Object?>());

    test('applies the requested presets', () {
      const base = VideoSettings();
      expect(base.applyPreset(VideoPreset.low).toJson(), containsPair('resolution', '720p'));
      expect(base.applyPreset(VideoPreset.low).fps, 25);
      expect(base.applyPreset(VideoPreset.low).videoBitrateKbps, 2000);
      expect(base.applyPreset(VideoPreset.high).videoBitrateKbps, 7000);
    });

    test('never forces values the hardware does not support', () {
      final front60 = const VideoSettings(fps: 60).constrainedTo(caps, 'front');
      expect(front60.fps, 30);
      final back60 = const VideoSettings(fps: 60).constrainedTo(caps, 'back');
      expect(back60.fps, 60);
      final tooFast = const VideoSettings(videoBitrateKbps: 50000).constrainedTo(caps, 'back');
      expect(tooFast.videoBitrateKbps, 12000);
      final only720 = DeviceCapabilities.fromJson({
        ...caps.toProtocolJson(),
        'resolutions': ['720p'],
      });
      expect(const VideoSettings().constrainedTo(only720, 'back').resolution, '720p');
    });

    test('swaps the frame size in portrait', () {
      expect(const VideoSettings().frameSize, (1920, 1080));
      expect(const VideoSettings(orientation: OrientationLock.portrait).frameSize, (1080, 1920));
    });

    test('serializes to the map expected by the native engine', () {
      final json = const VideoSettings(resolution: '720p', fps: 25, bitrateMode: BitrateMode.manual).toJson();
      expect(json, {
        'resolution': '720p',
        'fps': 25,
        'videoBitrateKbps': 5000,
        'audioBitrateKbps': 128,
        'bitrateMode': 'manual',
        'keyframeIntervalSec': 2,
        'orientation': 'landscape',
      });
      expect(VideoSettings.fromJson(json), const VideoSettings(resolution: '720p', fps: 25, bitrateMode: BitrateMode.manual));
    });
  });
}

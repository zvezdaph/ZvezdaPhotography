import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';

class RealtimePreviewException implements Exception {
  const RealtimePreviewException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => message;
}

enum RealtimePreviewStatus { idle, connecting, live, error }

/// Owns the phone camera only while the device is in PRE-LIVE.
///
/// The production path stays unchanged: START stops this publisher, releases
/// the camera and hands it to the native RootEncoder/SRT pipeline.
class RealtimePreviewPublisher extends ChangeNotifier {
  RealtimePreviewPublisher({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  Room? _room;
  LocalVideoTrack? _track;

  RealtimePreviewStatus status = RealtimePreviewStatus.idle;
  String? error;
  String facing = 'back';

  LocalVideoTrack? get track => _track;
  bool get active => status == RealtimePreviewStatus.connecting || status == RealtimePreviewStatus.live;

  Future<Map<String, Object?>> _credentials(Uri serverUrl, String deviceToken) async {
    final response = await _client
        .get(
          serverUrl.replace(path: '/api/livekit/device-token', query: null, fragment: null),
          headers: {'Authorization': 'Bearer $deviceToken'},
        )
        .timeout(const Duration(seconds: 12));

    Map<String, Object?> body = const {};
    try {
      body = (jsonDecode(response.body) as Map).cast<String, Object?>();
    } catch (_) {}

    if (response.statusCode >= 400) {
      final rawError = body['error'];
      final e = rawError is Map ? rawError.cast<String, Object?>() : const <String, Object?>{};
      throw RealtimePreviewException(
        e['code'] as String? ?? 'http_${response.statusCode}',
        e['message'] as String? ?? 'Anteprima realtime non disponibile',
      );
    }
    return body;
  }

  Future<void> start({
    required Uri serverUrl,
    required String deviceToken,
    required String initialFacing,
  }) async {
    if (active) return;
    status = RealtimePreviewStatus.connecting;
    error = null;
    facing = initialFacing == 'front' ? 'front' : 'back';
    notifyListeners();

    Room? room;
    LocalVideoTrack? track;
    try {
      final auth = await _credentials(serverUrl, deviceToken);
      final livekitUrl = auth['serverUrl'];
      final token = auth['participantToken'];
      if (livekitUrl is! String || token is! String) {
        throw const RealtimePreviewException('bad_response', 'Credenziali LiveKit incomplete');
      }

      await LiveKitClient.initialize();
      room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: false,
          dynacast: true,
          stopLocalTrackOnUnpublish: true,
        ),
      );
      await room.connect(livekitUrl, token);

      final options = CameraCaptureOptions(
        cameraPosition: facing == 'front' ? CameraPosition.front : CameraPosition.back,
        maxFrameRate: 25,
        params: VideoParametersPresets.h720_169,
      );
      track = await LocalVideoTrack.createCameraTrack(options);
      final participant = room.localParticipant;
      if (participant == null) {
        throw const RealtimePreviewException('room_not_ready', 'LiveKit non ha inizializzato il partecipante locale');
      }
      await participant.publishVideoTrack(track);

      _room = room;
      _track = track;
      status = RealtimePreviewStatus.live;
      notifyListeners();
    } catch (e) {
      if (track != null) {
        try {
          await track.stop();
        } catch (_) {}
      }
      if (room != null) {
        try {
          await room.disconnect();
        } catch (_) {}
        try {
          await room.dispose();
        } catch (_) {}
      }
      _room = null;
      _track = null;
      status = RealtimePreviewStatus.error;
      error = e is RealtimePreviewException ? e.message : 'Anteprima realtime non disponibile: $e';
      notifyListeners();
      if (e is RealtimePreviewException) rethrow;
      throw RealtimePreviewException('livekit_error', error!);
    }
  }

  Future<void> switchCamera(String target) async {
    final track = _track;
    if (track == null || status != RealtimePreviewStatus.live) {
      throw const RealtimePreviewException('preview_not_live', 'Anteprima realtime non attiva');
    }
    if (target != 'front' && target != 'back') {
      throw const RealtimePreviewException('invalid_camera', 'Camera non valida');
    }
    if (target == facing) return;
    await track.setCameraPosition(target == 'front' ? CameraPosition.front : CameraPosition.back);
    facing = target;
    notifyListeners();
  }

  Future<void> stop() async {
    final room = _room;
    final track = _track;
    _room = null;
    _track = null;
    status = RealtimePreviewStatus.idle;
    error = null;
    notifyListeners();

    if (track != null) {
      try {
        await track.stop();
      } catch (_) {}
    }
    if (room != null) {
      try {
        await room.disconnect();
      } catch (_) {}
      try {
        await room.dispose();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    final room = _room;
    final track = _track;
    _room = null;
    _track = null;
    if (track != null) {
      track.stop().catchError((_) => false);
    }
    if (room != null) {
      room.disconnect().catchError((_) {});
      room.dispose().catchError((_) => false);
    }
    _client.close();
    super.dispose();
  }
}

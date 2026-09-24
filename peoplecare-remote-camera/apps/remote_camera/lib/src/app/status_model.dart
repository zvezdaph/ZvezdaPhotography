import '../models/engine_state.dart';

/// Connection states shown to the operator (requirement: connecting,
/// connected, reconnecting, disconnected, error).
enum LinkState { connecting, connected, reconnecting, disconnected, error }

/// Traffic-light colors of the status indicators.
enum Light { green, yellow, red, off }

/// Big badge of the camera screen.
enum LiveBadge { live, paused, reconnecting, offline, error, connecting }

class StatusModel {
  /// Derives the transmission link state from the native engine state.
  static LinkState streamLink(EngineState state) => switch (state.streamStatus) {
        NativeStreamStatus.connecting => LinkState.connecting,
        NativeStreamStatus.live => LinkState.connected,
        NativeStreamStatus.reconnecting => LinkState.reconnecting,
        NativeStreamStatus.error => LinkState.error,
        NativeStreamStatus.idle || NativeStreamStatus.stopping => LinkState.disconnected,
      };

  /// LIVE only when the transport is really connected (never simulated).
  static LiveBadge badge(EngineState state) {
    switch (state.streamStatus) {
      case NativeStreamStatus.live:
        return state.paused ? LiveBadge.paused : LiveBadge.live;
      case NativeStreamStatus.reconnecting:
        return LiveBadge.reconnecting;
      case NativeStreamStatus.connecting:
        return LiveBadge.connecting;
      case NativeStreamStatus.error:
        return LiveBadge.error;
      case NativeStreamStatus.idle:
      case NativeStreamStatus.stopping:
        return LiveBadge.offline;
    }
  }

  static String badgeLabel(LiveBadge badge) => switch (badge) {
        LiveBadge.live => 'LIVE',
        LiveBadge.paused => 'PAUSA',
        LiveBadge.reconnecting => 'RECONNECTING',
        LiveBadge.connecting => 'CONNECTING',
        LiveBadge.offline => 'OFFLINE',
        LiveBadge.error => 'ERROR',
      };

  static Light cameraLight(EngineState state) => switch (state.cameraStatus) {
        CameraStatus.ready => Light.green,
        CameraStatus.starting => Light.yellow,
        CameraStatus.error => Light.red,
        CameraStatus.off => Light.off,
      };

  /// Cloudflare light: combines what the phone knows (transport) with what
  /// Cloudflare reports through the control plane (ingest state).
  static Light cloudflareLight(EngineState state, String? ingestState) {
    if (ingestState == 'error' || ingestState == 'disabled' || state.streamStatus == NativeStreamStatus.error) {
      return Light.red;
    }
    if (state.streamStatus == NativeStreamStatus.live) {
      return ingestState == 'offline' ? Light.yellow : Light.green;
    }
    if (state.streamStatus == NativeStreamStatus.connecting || state.streamStatus == NativeStreamStatus.reconnecting) {
      return Light.yellow;
    }
    if (ingestState == 'live') return Light.green;
    return Light.off;
  }

  static Light controlLight(LinkState control) => switch (control) {
        LinkState.connected => Light.green,
        LinkState.connecting || LinkState.reconnecting => Light.yellow,
        LinkState.error => Light.red,
        LinkState.disconnected => Light.red,
      };
}

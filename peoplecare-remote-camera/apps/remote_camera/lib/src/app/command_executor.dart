import '../engine/engine_bridge.dart';
import '../models/capabilities.dart';
import '../models/engine_state.dart';
import '../models/video_settings.dart';
import '../protocol/protocol.dart';

/// Actions the executor can perform on the camera (implemented by AppController).
abstract class CameraActions {
  DeviceCapabilities get capabilities;
  EngineState get engineState;
  VideoSettings get videoSettings;

  Future<Map<String, Object?>> startStream({required String source});
  Future<void> stopStream({required String source});
  Future<void> pause();
  Future<void> resume();
  Future<void> reconnect();
  Future<void> restartStream();
  Future<Map<String, Object?>> switchCamera(String facing);
  Future<Map<String, Object?>> setZoom(double zoom);
  Future<Map<String, Object?>> zoomBy(double step);
  Future<void> setAudioEnabled(bool enabled);
  Future<void> setVideoEnabled(bool enabled);
  Future<Map<String, Object?>> setTorch(bool enabled);
  Future<Map<String, Object?>> setAutoFocus(bool enabled);
  Future<Map<String, Object?>> focusAt(double x, double y);
  Future<Map<String, Object?>> setExposure(int index);
  Future<Map<String, Object?>> updateVideoSettings(VideoSettings settings);
  Future<Map<String, Object?>> setBitrate(BitrateMode mode, int? kbps);
  Future<Map<String, Object?>> setRecording(bool enabled);
}

class CommandFailure implements Exception {
  CommandFailure(this.code, this.message);
  final String code;
  final String message;
}

/// Executes a remote command and returns the ACK result. Unsupported
/// hardware features are refused with an explicit error: nothing is ever
/// acknowledged as done if it was not really executed.
class CommandExecutor {
  CommandExecutor(this.actions);

  final CameraActions actions;
  static const double defaultZoomStep = 0.5;

  Future<Map<String, Object?>> execute(DeviceCommand command) async {
    try {
      return await _run(command);
    } on EngineException catch (e) {
      throw CommandFailure(e.code, e.message);
    }
  }

  FacingCapabilities? get _facing => actions.capabilities.facing(actions.engineState.facing);

  Never _unsupported(String what) => throw CommandFailure('unsupported', '$what non supportato da questo telefono');

  Future<Map<String, Object?>> _run(DeviceCommand command) async {
    final value = command.value;
    switch (command.command) {
      case 'start_stream':
        return actions.startStream(source: command.issuedBy);
      case 'stop_stream':
        await actions.stopStream(source: command.issuedBy);
        return {'streamStatus': 'idle'};
      case 'pause':
        if (!actions.engineState.streaming) throw CommandFailure('not_streaming', 'Nessuna trasmissione attiva');
        await actions.pause();
        return {'paused': true};
      case 'resume':
        await actions.resume();
        return {'paused': false};
      case 'reconnect':
        await actions.reconnect();
        return {'reconnecting': true};
      case 'restart_stream':
        await actions.restartStream();
        return {'restarting': true};
      case 'switch_camera':
        final facing = value as String;
        if (actions.capabilities.facing(facing)?.available != true) {
          _unsupported(facing == 'front' ? 'Camera frontale' : 'Camera posteriore');
        }
        return actions.switchCamera(facing);
      case 'set_zoom':
        if (_facing?.zoomSupported != true) _unsupported('Zoom');
        return actions.setZoom((value as num).toDouble());
      case 'zoom_in':
      case 'zoom_out':
        if (_facing?.zoomSupported != true) _unsupported('Zoom');
        final step = (value as num?)?.toDouble() ?? defaultZoomStep;
        return actions.zoomBy(command.command == 'zoom_in' ? step : -step);
      case 'set_audio_enabled':
        await actions.setAudioEnabled(value as bool);
        return {'audioEnabled': value};
      case 'set_video_enabled':
        await actions.setVideoEnabled(value as bool);
        return {'videoEnabled': value};
      case 'set_torch':
        if (value == true && _facing?.torch != true) _unsupported('Torcia');
        return actions.setTorch(value as bool);
      case 'set_autofocus':
        if (_facing?.autofocus != true) _unsupported('Autofocus');
        return actions.setAutoFocus(value as bool);
      case 'focus_point':
        if (_facing?.focusPoint != true) _unsupported('Focus point');
        final point = (value as Map).cast<String, Object?>();
        return actions.focusAt((point['x'] as num).toDouble(), (point['y'] as num).toDouble());
      case 'set_exposure':
        if (_facing?.exposureSupported != true) _unsupported('Esposizione');
        return actions.setExposure(value as int);
      case 'set_resolution':
        final resolution = value as String;
        if (!actions.capabilities.resolutions.contains(resolution)) _unsupported('Risoluzione $resolution');
        return actions.updateVideoSettings(
          actions.videoSettings.copyWith(resolution: resolution).constrainedTo(actions.capabilities, actions.engineState.facing),
        );
      case 'set_fps':
        final fps = value as int;
        final resolution = actions.videoSettings.resolution;
        if (!actions.capabilities.supportsFps(actions.engineState.facing, resolution, fps)) {
          _unsupported('$fps fps a $resolution');
        }
        return actions.updateVideoSettings(actions.videoSettings.copyWith(fps: fps));
      case 'set_bitrate':
        final map = (value as Map).cast<String, Object?>();
        return actions.setBitrate(BitrateMode.parse(map['mode']), (map['kbps'] as num?)?.toInt());
      case 'set_preset':
        final preset = VideoPreset.parse(value);
        if (preset == null) throw CommandFailure('invalid_value', 'Preset sconosciuto');
        return actions.updateVideoSettings(
          actions.videoSettings.applyPreset(preset).constrainedTo(actions.capabilities, actions.engineState.facing),
        );
      case 'set_record':
        if (value == true && !actions.capabilities.recording) _unsupported('Registrazione locale');
        return actions.setRecording(value as bool);
      default:
        throw CommandFailure('unknown_command', 'Comando sconosciuto');
    }
  }
}

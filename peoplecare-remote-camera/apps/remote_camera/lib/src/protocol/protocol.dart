/// Control-plane protocol v1 (Dart side). Mirrors
/// cloudflare/worker/src/shared/protocol.ts; golden messages shared with the
/// Worker tests live in docs/protocol-fixtures.
library;

const int protocolVersion = 1;

const List<String> commandNames = [
  'start_stream',
  'stop_stream',
  'pause',
  'resume',
  'restart_stream',
  'reconnect',
  'switch_camera',
  'set_zoom',
  'zoom_in',
  'zoom_out',
  'set_audio_enabled',
  'set_video_enabled',
  'set_torch',
  'set_autofocus',
  'focus_point',
  'set_exposure',
  'set_resolution',
  'set_fps',
  'set_bitrate',
  'set_preset',
  'set_record',
];

final RegExp commandIdPattern = RegExp(r'^[A-Za-z0-9_-]{16,64}$');

class ProtocolException implements Exception {
  ProtocolException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'ProtocolException($code): $message';
}

/// Validates and normalizes the value of a command (same rules as the server).
Object? validateCommandValue(String command, Object? value) {
  Never fail(String message) => throw ProtocolException('invalid_value', message);
  switch (command) {
    case 'start_stream':
    case 'stop_stream':
    case 'pause':
    case 'resume':
    case 'restart_stream':
    case 'reconnect':
      if (value != null) fail('value must be empty');
      return null;
    case 'zoom_in':
    case 'zoom_out':
      if (value == null) return null;
      if (value is! num || value <= 0 || value > 5) fail('step must be in (0, 5]');
      return value.toDouble();
    case 'switch_camera':
      if (value != 'front' && value != 'back') fail("value must be 'front' or 'back'");
      return value;
    case 'set_zoom':
      if (value is! num || value < 0.1 || value > 100) fail('zoom must be in [0.1, 100]');
      return (value * 100).round() / 100;
    case 'set_audio_enabled':
    case 'set_video_enabled':
    case 'set_torch':
    case 'set_autofocus':
    case 'set_record':
      if (value is! bool) fail('value must be a boolean');
      return value;
    case 'focus_point':
      if (value is! Map) fail('value must be {x, y}');
      final x = value['x'];
      final y = value['y'];
      if (x is! num || y is! num || x < 0 || x > 1 || y < 0 || y > 1) fail('x and y must be in [0, 1]');
      return {'x': x.toDouble(), 'y': y.toDouble()};
    case 'set_exposure':
      if (value is! int || value < -100 || value > 100) fail('exposure must be an integer in [-100, 100]');
      return value;
    case 'set_resolution':
      if (value != '720p' && value != '1080p') fail('resolution must be 720p or 1080p');
      return value;
    case 'set_fps':
      if (value is! int || !const [25, 30, 50, 60].contains(value)) fail('fps must be one of 25, 30, 50, 60');
      return value;
    case 'set_bitrate':
      if (value is! Map) fail('value must be {mode, kbps}');
      final mode = value['mode'];
      final kbps = value['kbps'];
      if (mode == 'auto' && kbps == null) return {'mode': 'auto'};
      if (mode != 'auto' && mode != 'manual') fail('mode must be auto or manual');
      if (kbps is! num || kbps < 500 || kbps > 12000) fail('kbps must be in [500, 12000]');
      return {'mode': mode, 'kbps': kbps.round()};
    case 'set_preset':
      if (value != 'low' && value != 'standard' && value != 'high') fail('preset must be low, standard or high');
      return value;
    default:
      throw ProtocolException('unknown_command', 'unknown command $command');
  }
}

/// A command forwarded by the server to this phone.
class DeviceCommand {
  const DeviceCommand({
    required this.commandId,
    required this.seq,
    required this.command,
    required this.value,
    required this.issuedAt,
    required this.sentAt,
    required this.expiresAt,
    required this.issuedBy,
  });

  final String commandId;
  final int seq;
  final String command;
  final Object? value;
  final int issuedAt;
  final int sentAt;
  final int expiresAt;
  final String issuedBy;

  static DeviceCommand parse(Map<String, Object?> json) {
    if (json['v'] != protocolVersion) throw ProtocolException('unsupported_version', 'unsupported protocol version');
    if (json['type'] != 'command') throw ProtocolException('invalid_message', 'type must be command');
    final id = json['commandId'];
    if (id is! String || !commandIdPattern.hasMatch(id)) throw ProtocolException('invalid_message', 'invalid commandId');
    final command = json['command'];
    if (command is! String || !commandNames.contains(command)) {
      throw ProtocolException('unknown_command', 'unknown command');
    }
    int number(String key) {
      final v = json[key];
      if (v is! num) throw ProtocolException('invalid_message', '$key must be a number');
      return v.toInt();
    }

    return DeviceCommand(
      commandId: id,
      seq: number('seq'),
      command: command,
      value: validateCommandValue(command, json['value']),
      issuedAt: number('issuedAt'),
      sentAt: number('sentAt'),
      expiresAt: number('expiresAt'),
      issuedBy: json['issuedBy'] is String ? json['issuedBy'] as String : 'regia',
    );
  }
}

/// Messages sent by the phone.
class Outgoing {
  static Map<String, Object?> hello({
    required Map<String, Object?> device,
    required Map<String, Object?> capabilities,
    required Map<String, Object?> state,
  }) =>
      {'v': protocolVersion, 'type': 'hello', 'device': device, 'capabilities': capabilities, 'state': state};

  static Map<String, Object?> state(Map<String, Object?> state, {Map<String, Object?>? capabilities}) => {
        'v': protocolVersion,
        'type': 'state',
        'state': state,
        'capabilities': ?capabilities,
      };

  static Map<String, Object?> telemetry(Map<String, Object?> telemetry) =>
      {'v': protocolVersion, 'type': 'telemetry', 'telemetry': telemetry};

  static Map<String, Object?> ping(int t) => {'v': protocolVersion, 'type': 'ping', 't': t};

  static Map<String, Object?> configRequest() => {'v': protocolVersion, 'type': 'config_request'};

  static Map<String, Object?> log(String level, String message) =>
      {'v': protocolVersion, 'type': 'log', 'level': level, 'message': message};

  static Map<String, Object?> ackReceived(String commandId, int ts) => {
        'v': protocolVersion,
        'type': 'ack',
        'commandId': commandId,
        'stage': 'received',
        'ok': true,
        'result': null,
        'error': null,
        'ts': ts,
      };

  static Map<String, Object?> ackCompleted(String commandId, Map<String, Object?>? result, int ts) => {
        'v': protocolVersion,
        'type': 'ack',
        'commandId': commandId,
        'stage': 'completed',
        'ok': true,
        'result': result,
        'error': null,
        'ts': ts,
      };

  static Map<String, Object?> ackFailed(String commandId, String code, String message, int ts) => {
        'v': protocolVersion,
        'type': 'ack',
        'commandId': commandId,
        'stage': 'completed',
        'ok': false,
        'result': null,
        'error': {'code': code, 'message': message},
        'ts': ts,
      };
}

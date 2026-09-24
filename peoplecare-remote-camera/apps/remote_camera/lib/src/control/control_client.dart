import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app/status_model.dart';
import '../protocol/command_guard.dart';
import '../protocol/protocol.dart';
import 'reconnect_policy.dart';
import 'transport.dart';

typedef Clock = int Function();

/// Handlers invoked by [ControlClient]. All of them are optional.
class ControlHandlers {
  const ControlHandlers({
    this.onStatus,
    this.onWelcome,
    this.onCommand,
    this.onConfig,
    this.onCloudflareStatus,
    this.onCameraInfo,
    this.onRevoked,
    this.onUnauthorized,
    this.onLog,
  });

  final void Function(LinkState status)? onStatus;
  final void Function(Map<String, Object?> welcome)? onWelcome;
  final void Function(DeviceCommand command)? onCommand;
  final void Function(Map<String, Object?> message)? onConfig;
  final void Function(Map<String, Object?> message)? onCloudflareStatus;
  final void Function(Map<String, Object?> message)? onCameraInfo;
  final void Function()? onRevoked;
  final void Function()? onUnauthorized;
  final void Function(String level, String message)? onLog;
}

/// Persistent, authenticated WebSocket from the phone to the control plane
/// (Cloudflare Worker + Durable Object). Reconnects automatically with
/// exponential backoff, detects half-open connections with an application
/// heartbeat, and validates every command (anti replay) before handing it
/// to the app.
class ControlClient {
  ControlClient({
    required this.serverUrl,
    required this.deviceToken,
    required this.handlers,
    TransportConnector? connector,
    http.Client? httpClient,
    Clock? clock,
    ReconnectPolicy? policy,
    this.heartbeatInterval = const Duration(seconds: 15),
    this.silenceTimeout = const Duration(seconds: 45),
  })  : _connector = connector ?? IoWebSocketTransport.connect,
        _http = httpClient ?? http.Client(),
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _policy = policy ?? ReconnectPolicy();

  final Uri serverUrl;
  final String deviceToken;
  final ControlHandlers handlers;
  final Duration heartbeatInterval;
  final Duration silenceTimeout;
  final TransportConnector _connector;
  final http.Client _http;
  final Clock _clock;
  final ReconnectPolicy _policy;
  final CommandGuard guard = CommandGuard();

  ControlTransport? _transport;
  StreamSubscription<String>? _subscription;
  Timer? _reconnectTimer;
  Timer? _heartbeat;
  bool _running = false;
  bool _revoked = false;
  bool _everConnected = false;
  int _lastMessageAt = 0;
  LinkState _status = LinkState.disconnected;
  String? connectionId;

  LinkState get status => _status;
  bool get connected => _status == LinkState.connected;
  int get reconnectAttempts => _policy.attempts;

  /// WebSocket URL of the device endpoint (https -> wss, http -> ws).
  static Uri deviceSocketUrl(Uri server) {
    final scheme = server.scheme == 'http' ? 'ws' : 'wss';
    return server.replace(scheme: scheme, path: '/ws/device', query: null, fragment: null);
  }

  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  /// Stops the client and closes the socket. It returns immediately: neither
  /// the subscription cancel nor the WebSocket close handshake is awaited
  /// (with a dead network the handshake can last until the TCP timeout, and
  /// stop() is also called from inside message handlers).
  Future<void> stop() async {
    _running = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    final subscription = _subscription;
    _subscription = null;
    final transport = _transport;
    _transport = null;
    if (!_revoked) _setStatus(LinkState.disconnected);
    unawaited(subscription?.cancel());
    if (transport != null) unawaited(transport.close(1000, 'bye').catchError((Object _) {}));
  }

  /// Sends a message if connected. Returns false when it could not be sent
  /// (messages are never queued: state is re-sent on reconnection).
  bool send(Map<String, Object?> message) {
    final transport = _transport;
    if (transport == null || _status != LinkState.connected) return false;
    try {
      transport.send(jsonEncode(message));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Drops the current socket and reconnects now (e.g. after a network change).
  void reconnectNow() {
    if (!_running) return;
    _policy.reset();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final transport = _transport;
    if (transport != null) {
      unawaited(transport.close(4000, 'network changed'));
    } else {
      _connect();
    }
  }

  void _setStatus(LinkState status) {
    if (_status == status) return;
    _status = status;
    handlers.onStatus?.call(status);
  }

  Future<void> _connect() async {
    if (!_running) return;
    _setStatus(_everConnected ? LinkState.reconnecting : LinkState.connecting);
    final url = deviceSocketUrl(serverUrl);
    ControlTransport transport;
    try {
      transport = await _connector(url, {
        'Authorization': 'Bearer $deviceToken',
        'User-Agent': 'PeopleCareRemoteCamera/1 (Android)',
      });
    } catch (e) {
      handlers.onLog?.call('warning', 'Regia non raggiungibile: ${_describe(e)}');
      if (await _tokenRejected()) return;
      _scheduleReconnect();
      return;
    }
    if (!_running) {
      await transport.close(1000, 'stopped');
      return;
    }
    _transport = transport;
    _lastMessageAt = _clock();
    _subscription = transport.messages.listen(
      _onMessage,
      onError: (Object error) => handlers.onLog?.call('warning', 'Errore WebSocket: ${_describe(error)}'),
      onDone: () => _onClosed(transport),
      cancelOnError: false,
    );
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(heartbeatInterval, (_) => _tick());
  }

  /// A failed upgrade does not expose the HTTP status: probe the endpoint
  /// with a plain GET (the server answers 401 for revoked tokens, 426 otherwise).
  Future<bool> _tokenRejected() async {
    try {
      final probeUrl = serverUrl.replace(path: '/ws/device', query: null, fragment: null);
      final response = await _http
          .get(probeUrl, headers: {'Authorization': 'Bearer $deviceToken'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 401) {
        _running = false;
        _setStatus(LinkState.error);
        handlers.onLog?.call('error', 'Token dispositivo rifiutato dalla regia (revocato)');
        handlers.onUnauthorized?.call();
        return true;
      }
    } catch (_) {
      // Network down: keep retrying.
    }
    return false;
  }

  void _tick() {
    final transport = _transport;
    if (transport == null) return;
    if (_clock() - _lastMessageAt > silenceTimeout.inMilliseconds) {
      handlers.onLog?.call('warning', 'Nessuna risposta dalla regia da ${silenceTimeout.inSeconds}s: riconnessione');
      unawaited(transport.close(4000, 'heartbeat timeout'));
      return;
    }
    if (_status == LinkState.connected) send(Outgoing.ping(_clock()));
  }

  void _onClosed(ControlTransport transport) {
    if (_transport != transport) return;
    _transport = null;
    _heartbeat?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    final code = transport.closeCode;
    if (code == 4001) {
      _onRevoked();
      return;
    }
    if (code == 4002) {
      handlers.onLog?.call('warning', 'Connessione sostituita da un altro collegamento con lo stesso token');
    }
    if (!_running) {
      _setStatus(LinkState.disconnected);
      return;
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_running) return;
    _setStatus(_everConnected ? LinkState.reconnecting : LinkState.connecting);
    _reconnectTimer?.cancel();
    final delay = _policy.nextDelay();
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      _connect();
    });
  }

  void _onMessage(String raw) {
    _lastMessageAt = _clock();
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (decoded is! Map) return;
    final message = decoded.cast<String, Object?>();
    if (message['v'] != protocolVersion) return;
    switch (message['type']) {
      case 'welcome':
        _everConnected = true;
        _policy.reset();
        connectionId = message['connId'] as String?;
        guard.startSession(connectionId ?? 'unknown');
        final serverTime = message['serverTime'];
        if (serverTime is num) guard.serverOffsetMs = serverTime.toInt() - _clock();
        _setStatus(LinkState.connected);
        handlers.onWelcome?.call(message);
        send(Outgoing.ping(_clock()));
      case 'pong':
        final t = message['t'];
        final serverTime = message['serverTime'];
        if (t is num && serverTime is num) {
          guard.updateOffset(serverTime: serverTime.toInt(), sentAtLocal: t.toInt(), receivedAtLocal: _clock());
        }
      case 'command':
        _onCommand(message);
      case 'config':
        handlers.onConfig?.call(message);
      case 'cloudflare_status':
        handlers.onCloudflareStatus?.call(message);
      case 'camera_info':
        handlers.onCameraInfo?.call(message);
      case 'revoked':
        _onRevoked();
      case 'error':
        handlers.onLog?.call('warning', 'Regia: ${message['message'] ?? message['code']}');
      default:
        break;
    }
  }

  /// The server sends {"type":"revoked"} and then closes with 4001: the app
  /// is notified only once.
  void _onRevoked() {
    _running = false;
    _reconnectTimer?.cancel();
    _heartbeat?.cancel();
    if (_revoked) return;
    _revoked = true;
    _setStatus(LinkState.error);
    handlers.onLog?.call('error', 'Dispositivo revocato dalla regia');
    handlers.onRevoked?.call();
  }

  void _onCommand(Map<String, Object?> message) {
    final DeviceCommand command;
    try {
      command = DeviceCommand.parse(message);
    } on ProtocolException catch (e) {
      final id = message['commandId'];
      if (id is String && commandIdPattern.hasMatch(id)) {
        send(Outgoing.ackFailed(id, e.code, e.message, _clock()));
      }
      handlers.onLog?.call('warning', 'Comando non valido rifiutato: ${e.message}');
      return;
    }
    final verdict = guard.check(command, _clock());
    if (verdict is Rejected) {
      send(Outgoing.ackFailed(command.commandId, verdict.code, verdict.message, _clock()));
      handlers.onLog?.call('warning', 'Comando ${command.command} rifiutato: ${verdict.message}');
      return;
    }
    send(Outgoing.ackReceived(command.commandId, _clock()));
    handlers.onCommand?.call(command);
  }

  String _describe(Object error) {
    final text = error.toString();
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }
}

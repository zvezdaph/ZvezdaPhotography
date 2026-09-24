import 'dart:async';
import 'dart:io';

/// Minimal WebSocket abstraction so that the control client can be tested
/// without network.
abstract class ControlTransport {
  Stream<String> get messages;
  Future<void> get done;
  int? get closeCode;
  String? get closeReason;
  void send(String data);
  Future<void> close([int code = 1000, String reason = '']);
}

typedef TransportConnector = Future<ControlTransport> Function(Uri url, Map<String, String> headers);

/// Real transport: dart:io WebSocket (TLS for wss://). The device token travels
/// in the Authorization header, never in the URL.
class IoWebSocketTransport implements ControlTransport {
  IoWebSocketTransport._(this._socket) {
    _socket.pingInterval = const Duration(seconds: 20);
  }

  final WebSocket _socket;

  static Future<ControlTransport> connect(Uri url, Map<String, String> headers) async {
    // The socket is owned by the returned transport and closed by ControlClient.
    // ignore: close_sinks
    final socket = await WebSocket.connect(url.toString(), headers: headers).timeout(const Duration(seconds: 15));
    return IoWebSocketTransport._(socket);
  }

  @override
  Stream<String> get messages => _socket.where((event) => event is String).cast<String>();

  @override
  Future<void> get done => _socket.done;

  @override
  int? get closeCode => _socket.closeCode;

  @override
  String? get closeReason => _socket.closeReason;

  @override
  void send(String data) => _socket.add(data);

  @override
  Future<void> close([int code = 1000, String reason = '']) => _socket.close(code, reason);
}

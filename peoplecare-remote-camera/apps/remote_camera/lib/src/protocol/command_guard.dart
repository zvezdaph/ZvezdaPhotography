import 'dart:collection';

import 'protocol.dart';

sealed class GuardResult {
  const GuardResult();
}

class Accepted extends GuardResult {
  const Accepted();
}

class Rejected extends GuardResult {
  const Rejected(this.code, this.message);
  final String code;
  final String message;
}

/// Anti-replay checks performed by the phone on every command, in addition
/// to the checks of the server:
///  - a command id is executed at most once (LRU of recent ids);
///  - sequence numbers must increase within a control session;
///  - expired commands (server clock) are refused.
class CommandGuard {
  CommandGuard({this.maxRemembered = 512, this.toleranceMs = 3000});

  final int maxRemembered;
  final int toleranceMs;
  final LinkedHashSet<String> _seen = LinkedHashSet<String>();
  int _lastSeq = 0;
  String? _sessionId;

  /// Offset between the server clock and the local clock (server - local).
  int serverOffsetMs = 0;

  int get lastSeq => _lastSeq;

  /// A new control session (welcome with a new connection id) restarts the
  /// sequence check; remembered command ids are kept.
  void startSession(String sessionId) {
    if (_sessionId == sessionId) return;
    _sessionId = sessionId;
    _lastSeq = 0;
  }

  /// Estimates the server clock offset from a ping/pong exchange.
  void updateOffset({required int serverTime, required int sentAtLocal, required int receivedAtLocal}) {
    final rtt = receivedAtLocal - sentAtLocal;
    if (rtt < 0 || rtt > 30000) return;
    serverOffsetMs = serverTime + rtt ~/ 2 - receivedAtLocal;
  }

  int serverNow(int localNow) => localNow + serverOffsetMs;

  GuardResult check(DeviceCommand command, int localNow) {
    if (_seen.contains(command.commandId)) {
      return const Rejected('duplicate_command', 'Comando già eseguito (replay rifiutato)');
    }
    if (command.seq <= _lastSeq) {
      return Rejected('replay_rejected', 'Sequenza non valida (${command.seq} <= $_lastSeq)');
    }
    final now = serverNow(localNow);
    if (now > command.expiresAt + toleranceMs) {
      return const Rejected('command_expired', 'Comando scaduto prima di arrivare al telefono');
    }
    if (command.sentAt > now + 60000) {
      return const Rejected('clock_skew', 'Timestamp del comando nel futuro');
    }
    _seen.add(command.commandId);
    while (_seen.length > maxRemembered) {
      _seen.remove(_seen.first);
    }
    _lastSeq = command.seq;
    return const Accepted();
  }
}

/// Validates a raw command and returns it or throws [ProtocolException].
DeviceCommand parseCommand(Map<String, Object?> json) => DeviceCommand.parse(json);

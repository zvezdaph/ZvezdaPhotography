import 'dart:async';
import 'dart:convert';

import '../../domain/domain.dart';
import 'entity_json.dart';

/// Messaggio Server-Sent Events (`text/event-stream`).
class SseMessage {
  const SseMessage({required this.event, required this.data, this.id});

  /// Tipo di evento (`message` se il server non lo indica).
  final String event;
  final String data;
  final String? id;
}

/// Converte le righe di uno stream SSE in messaggi.
///
/// Gestisce commenti/heartbeat (`: ping`), dati su più righe e l'`id`
/// dell'ultimo evento, da reinviare in `Last-Event-ID` alla riconnessione.
class SseDecoder extends StreamTransformerBase<String, SseMessage> {
  const SseDecoder();

  @override
  Stream<SseMessage> bind(Stream<String> lines) async* {
    String? event;
    String? id;
    final data = <String>[];
    await for (final raw in lines) {
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      if (line.isEmpty) {
        if (data.isNotEmpty) {
          yield SseMessage(
            event: event ?? 'message',
            data: data.join('\n'),
            id: id,
          );
        }
        event = null;
        data.clear();
        continue;
      }
      if (line.startsWith(':')) continue;
      final colon = line.indexOf(':');
      final field = colon < 0 ? line : line.substring(0, colon);
      var value = colon < 0 ? '' : line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      switch (field) {
        case 'event':
          event = value;
        case 'data':
          data.add(value);
        case 'id':
          id = value;
      }
    }
  }
}

/// Contenuto utile di un messaggio del canale `GET /events`.
sealed class LiveMessage {
  const LiveMessage();
}

/// "Questi dati sono cambiati": le schermate interessate rileggono.
final class LiveOperationalEvent extends LiveMessage {
  const LiveOperationalEvent(this.event);

  final OperationalEvent event;
}

/// Nuova notifica per l'utente della Centrale.
final class LiveNotification extends LiveMessage {
  const LiveNotification(this.notification);

  final AppNotification notification;
}

/// Interpreta un messaggio SSE; `null` per tipi o argomenti sconosciuti e per
/// dati non leggibili, che vanno ignorati (compatibilità con versioni future
/// del sistema).
LiveMessage? liveMessageFromSse(SseMessage message) {
  final Object? decoded;
  try {
    decoded = jsonDecode(message.data);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final json = decoded.cast<String, Object?>();
  switch (message.event) {
    case 'operational_event':
      final event = operationalEventFromJson(json);
      return event == null ? null : LiveOperationalEvent(event);
    case 'notification':
      return LiveNotification(notificationFromJson(json));
    default:
      return null;
  }
}

/// Categoria di dati toccata da un evento in tempo reale.
enum OperationalEventTopic {
  servizi('servizi'),
  operatori('operatori'),
  strutture('strutture'),
  tipologieServizio('tipologie_servizio'),
  richiesteModifica('richieste_modifica'),
  documenti('documenti'),
  notifiche('notifiche'),
  registroAttivita('registro_attivita');

  const OperationalEventTopic(this.code);

  final String code;

  static OperationalEventTopic? tryFromCode(String code) {
    for (final topic in values) {
      if (topic.code == code) return topic;
    }
    return null;
  }
}

/// Evento in tempo reale: "questi dati sono cambiati".
///
/// Serve alle schermate aperte per aggiornarsi senza ricaricare a mano.
/// Non trasporta i dati: chi lo riceve rilegge dal repository.
class OperationalEvent {
  const OperationalEvent({
    required this.topic,
    this.entityId,
    required this.occurredAt,
  });

  final OperationalEventTopic topic;
  final String? entityId;
  final DateTime occurredAt;
}

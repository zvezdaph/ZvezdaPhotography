/// Tipo di notifica operativa.
enum NotificationType {
  richiestaModifica('richiesta_modifica'),
  servizioIniziato('servizio_iniziato'),
  servizioTerminato('servizio_terminato'),
  documentoRicevuto('documento_ricevuto'),
  servizioProblematico('servizio_problematico'),

  /// Altre comunicazioni operative.
  operativa('operativa');

  const NotificationType(this.code);

  final String code;

  static NotificationType fromCode(String code) => values.firstWhere(
    (type) => type.code == code,
    orElse: () => NotificationType.operativa,
  );
}

/// Gravità della notifica.
enum NotificationSeverity {
  info('info'),
  attenzione('attenzione'),
  critica('critica');

  const NotificationSeverity(this.code);

  final String code;

  static NotificationSeverity fromCode(String code) => values.firstWhere(
    (severity) => severity.code == code,
    orElse: () => NotificationSeverity.info,
  );
}

/// Notifica destinata agli utenti della Centrale.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.severity,
    required this.title,
    required this.message,
    required this.createdAt,
    this.readAt,
    this.serviceId,
    this.operatorId,
    this.changeRequestId,
    this.documentId,
  });

  final String id;
  final NotificationType type;
  final NotificationSeverity severity;
  final String title;
  final String message;
  final DateTime createdAt;
  final DateTime? readAt;

  /// Collegamenti facoltativi alle entità coinvolte.
  final String? serviceId;
  final String? operatorId;
  final String? changeRequestId;
  final String? documentId;

  bool get isRead => readAt != null;

  AppNotification markRead(DateTime at) => AppNotification(
    id: id,
    type: type,
    severity: severity,
    title: title,
    message: message,
    createdAt: createdAt,
    readAt: readAt ?? at,
    serviceId: serviceId,
    operatorId: operatorId,
    changeRequestId: changeRequestId,
    documentId: documentId,
  );
}

import '../../domain/domain.dart';
import 'formatters.dart';

/// Etichette italiane dei valori di dominio.

extension ServiceStatusLabel on ServiceStatus {
  String get label => switch (this) {
    ServiceStatus.daAssegnare => 'Da assegnare',
    ServiceStatus.assegnato => 'Assegnato',
    ServiceStatus.inCorso => 'In corso',
    ServiceStatus.completato => 'Completato',
    ServiceStatus.annullato => 'Annullato',
    ServiceStatus.nonEseguito => 'Non eseguito',
    ServiceStatus.daRiprogrammare => 'Da riprogrammare',
  };
}

extension ServicePriorityLabel on ServicePriority {
  String get label => switch (this) {
    ServicePriority.bassa => 'Bassa',
    ServicePriority.normale => 'Normale',
    ServicePriority.alta => 'Alta',
    ServicePriority.urgente => 'Urgente',
  };
}

extension OperatorStatusLabel on OperatorStatus {
  String get label => switch (this) {
    OperatorStatus.attivo => 'Attivo',
    OperatorStatus.sospeso => 'Sospeso',
    OperatorStatus.disabilitato => 'Disabilitato',
  };
}

extension AccountStatusLabel on AccountStatus {
  String get label => switch (this) {
    AccountStatus.attivo => 'Attivo',
    AccountStatus.invitato => 'Invito inviato',
    AccountStatus.bloccato => 'Bloccato',
  };
}

extension FacilityKindLabel on FacilityKind {
  String get label => switch (this) {
    FacilityKind.rsa => 'RSA',
    FacilityKind.centroDiurno => 'Centro diurno',
    FacilityKind.servizioDomiciliare => 'Servizio domiciliare',
    FacilityKind.comunitaAlloggio => 'Comunità alloggio',
    FacilityKind.ambulatorio => 'Ambulatorio',
    FacilityKind.altro => 'Altro',
  };
}

extension ChangeRequestReasonLabel on ChangeRequestReason {
  String get label => switch (this) {
    ChangeRequestReason.problemaOrario => 'Problema di orario',
    ChangeRequestReason.sovrapposizione => 'Sovrapposizione',
    ChangeRequestReason.indisponibilita => 'Indisponibilità',
    ChangeRequestReason.problemaLogistico => 'Problema logistico',
    ChangeRequestReason.imprevisto => 'Imprevisto',
    ChangeRequestReason.altro => 'Altro',
  };
}

extension ChangeRequestStatusLabel on ChangeRequestStatus {
  String get label => switch (this) {
    ChangeRequestStatus.inAttesa => 'In attesa',
    ChangeRequestStatus.inLavorazione => 'In lavorazione',
    ChangeRequestStatus.chiusa => 'Chiusa',
  };
}

extension ChangeRequestOutcomeLabel on ChangeRequestOutcome {
  String get label => switch (this) {
    ChangeRequestOutcome.orarioModificato => 'Orario modificato',
    ChangeRequestOutcome.riassegnato => 'Riassegnato',
    ChangeRequestOutcome.assegnazioneMantenuta => 'Assegnazione mantenuta',
  };
}

extension DocumentOwnerTypeLabel on DocumentOwnerType {
  String get label => switch (this) {
    DocumentOwnerType.servizio => 'Servizio',
    DocumentOwnerType.operatore => 'Operatore',
    DocumentOwnerType.paziente => 'Paziente',
    DocumentOwnerType.centrale => 'Centrale',
  };

  String get pluralLabel => switch (this) {
    DocumentOwnerType.servizio => 'Servizi',
    DocumentOwnerType.operatore => 'Operatori',
    DocumentOwnerType.paziente => 'Pazienti',
    DocumentOwnerType.centrale => 'Centrale',
  };
}

extension DocumentCategoryLabel on DocumentCategory {
  String get label => switch (this) {
    DocumentCategory.pianoAssistenziale => 'Piano assistenziale',
    DocumentCategory.consenso => 'Consenso',
    DocumentCategory.referto => 'Referto / prescrizione',
    DocumentCategory.verbale => 'Verbale',
    DocumentCategory.foglioFirma => 'Foglio firma',
    DocumentCategory.certificato => 'Certificato / attestato',
    DocumentCategory.documentoIdentita => 'Documento d\'identità',
    DocumentCategory.procedura => 'Procedura / circolare',
    DocumentCategory.fotografia => 'Fotografia',
    DocumentCategory.altro => 'Altro',
  };
}

extension DocumentSourceLabel on DocumentSource {
  String get label => switch (this) {
    DocumentSource.centrale => 'Centrale',
    DocumentSource.operatore => 'App operatore',
    DocumentSource.sistema => 'Sistema',
  };
}

extension NotificationTypeLabel on NotificationType {
  String get label => switch (this) {
    NotificationType.richiestaModifica => 'Richiesta di modifica',
    NotificationType.servizioIniziato => 'Servizio iniziato',
    NotificationType.servizioTerminato => 'Servizio terminato',
    NotificationType.documentoRicevuto => 'Documento ricevuto',
    NotificationType.servizioProblematico => 'Servizio problematico',
    NotificationType.operativa => 'Operativa',
  };
}

extension NotificationSeverityLabel on NotificationSeverity {
  String get label => switch (this) {
    NotificationSeverity.info => 'Informativa',
    NotificationSeverity.attenzione => 'Attenzione',
    NotificationSeverity.critica => 'Critica',
  };
}

extension ActorKindLabel on ActorKind {
  String get label => switch (this) {
    ActorKind.centrale => 'Centrale',
    ActorKind.operatore => 'Operatore',
    ActorKind.sistema => 'Sistema',
  };
}

extension AuditEntityTypeLabel on AuditEntityType {
  String get label => switch (this) {
    AuditEntityType.servizio => 'Servizio',
    AuditEntityType.operatore => 'Operatore',
    AuditEntityType.struttura => 'Struttura',
    AuditEntityType.tipologiaServizio => 'Tipologia servizio',
    AuditEntityType.richiestaModifica => 'Richiesta di modifica',
    AuditEntityType.documento => 'Documento',
    AuditEntityType.sessione => 'Sessione',
  };
}

/// Etichetta leggibile di un codice azione del registro attività.
String auditActionLabel(String action) => switch (action) {
  AuditActions.serviceCreated => 'Servizio creato',
  AuditActions.serviceUpdated => 'Servizio modificato',
  AuditActions.serviceRescheduled => 'Servizio riprogrammato',
  AuditActions.serviceReassigned => 'Assegnazione modificata',
  AuditActions.serviceCancelled => 'Servizio annullato',
  AuditActions.serviceDeleted => 'Servizio eliminato',
  AuditActions.serviceMarkedToReschedule => 'Segnato da riprogrammare',
  AuditActions.serviceStarted => 'Servizio iniziato',
  AuditActions.serviceCompleted => 'Servizio terminato',
  AuditActions.serviceNotExecuted => 'Servizio non eseguito',
  AuditActions.documentUploaded => 'Documento caricato',
  AuditActions.documentReceived => 'Documento ricevuto',
  AuditActions.documentReviewed => 'Documento verificato',
  AuditActions.documentDeleted => 'Documento eliminato',
  AuditActions.changeRequestReceived => 'Richiesta ricevuta',
  AuditActions.changeRequestReplied => 'Risposta inviata',
  AuditActions.changeRequestClosed => 'Richiesta chiusa',
  AuditActions.operatorCreated => 'Operatore creato',
  AuditActions.operatorUpdated => 'Operatore modificato',
  AuditActions.operatorStatusChanged => 'Stato operatore modificato',
  AuditActions.operatorAccountLinked => 'Account collegato',
  AuditActions.operatorAccountUnlinked => 'Account scollegato',
  AuditActions.facilityCreated => 'Struttura creata',
  AuditActions.facilityUpdated => 'Struttura modificata',
  AuditActions.serviceTypeCreated => 'Tipologia creata',
  AuditActions.serviceTypeUpdated => 'Tipologia modificata',
  _ => action,
};

extension ServiceAlertKindLabel on ServiceAlertKind {
  String get label => switch (this) {
    ServiceAlertKind.avvioInRitardo => 'Avvio in ritardo',
    ServiceAlertKind.sforamento => 'Oltre l\'orario previsto',
    ServiceAlertKind.sovrapposizione => 'Sovrapposizione',
    ServiceAlertKind.daAssegnareImminente => 'Da assegnare a breve',
    ServiceAlertKind.daRiprogrammare => 'Da riprogrammare',
    ServiceAlertKind.nonEseguito => 'Non eseguito',
    ServiceAlertKind.operatoreNonAttivo => 'Operatore non attivo',
    ServiceAlertKind.richiestaModificaAperta => 'Richiesta di modifica aperta',
  };
}

/// Descrizione di un'anomalia per l'operatore di centrale.
String describeAlert(ServiceAlert alert, DateTime now) {
  final service = alert.service;
  switch (alert.kind) {
    case ServiceAlertKind.avvioInRitardo:
      return 'Previsto alle ${Fmt.time(service.scheduledStart)}, non ancora '
          'avviato (${alert.delay!.inMinutes} min).';
    case ServiceAlertKind.sforamento:
      return 'In corso oltre la fine prevista delle '
          '${Fmt.time(service.scheduledEnd)} (+${alert.delay!.inMinutes} min).';
    case ServiceAlertKind.sovrapposizione:
      final other = alert.otherService!;
      return 'Si sovrappone a ${other.code} '
          '(${Fmt.timeRange(other.scheduledStart, other.scheduledEnd)}).';
    case ServiceAlertKind.daAssegnareImminente:
      return service.scheduledStart.isBefore(now)
          ? 'Doveva iniziare alle ${Fmt.time(service.scheduledStart)} e non ha operatore.'
          : 'Inizia ${Fmt.relative(service.scheduledStart, now)} e non ha operatore.';
    case ServiceAlertKind.daRiprogrammare:
      return service.statusReason ?? 'In attesa di un nuovo orario.';
    case ServiceAlertKind.nonEseguito:
      return service.statusReason ?? 'Segnalato come non eseguito.';
    case ServiceAlertKind.operatoreNonAttivo:
      return 'Assegnato a un operatore sospeso o disabilitato.';
    case ServiceAlertKind.richiestaModificaAperta:
      return 'L\'operatore ha inviato una richiesta di modifica.';
  }
}

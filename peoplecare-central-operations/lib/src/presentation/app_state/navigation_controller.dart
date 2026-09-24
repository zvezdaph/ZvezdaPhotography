import 'package:flutter/material.dart';

import '../../domain/domain.dart';

/// Sezioni principali dell'applicazione, nell'ordine della barra laterale.
enum AppSection {
  dashboard('Dashboard', Icons.space_dashboard_outlined, Icons.space_dashboard),
  calendar(
    'Calendario operativo',
    Icons.calendar_month_outlined,
    Icons.calendar_month,
  ),
  services('Servizi', Icons.assignment_outlined, Icons.assignment),
  changeRequests(
    'Richieste di modifica',
    Icons.edit_calendar_outlined,
    Icons.edit_calendar,
  ),
  notifications(
    'Notifiche',
    Icons.notifications_none_outlined,
    Icons.notifications,
  ),
  operators('Operatori', Icons.badge_outlined, Icons.badge),
  facilities('Strutture', Icons.apartment_outlined, Icons.apartment),
  serviceTypes(
    'Tipologie di servizio',
    Icons.category_outlined,
    Icons.category,
  ),
  documents('Documenti', Icons.folder_open_outlined, Icons.folder_open),
  reports('Report', Icons.insights_outlined, Icons.insights),
  audit(
    'Registro attività',
    Icons.manage_history_outlined,
    Icons.manage_history,
  );

  const AppSection(this.title, this.icon, this.selectedIcon);

  final String title;
  final IconData icon;
  final IconData selectedIcon;

  /// Gruppo della barra laterale.
  String get group => switch (this) {
    dashboard ||
    calendar ||
    services ||
    changeRequests ||
    notifications => 'Operatività',
    operators || facilities || serviceTypes => 'Anagrafiche',
    documents || reports || audit => 'Archivio e controllo',
  };
}

/// Richiesta di aprire una sezione in uno stato preciso.
sealed class NavigationIntent {
  const NavigationIntent();
}

/// Gestione servizi con filtri preimpostati.
final class ServicesFilterIntent extends NavigationIntent {
  const ServicesFilterIntent({
    this.statuses = const {},
    this.range,
    this.operatorId,
    this.facilityId,
    this.patientId,
    this.unassignedOnly = false,
  });

  final Set<ServiceStatus> statuses;
  final DateRange? range;
  final String? operatorId;
  final String? facilityId;
  final String? patientId;
  final bool unassignedOnly;
}

/// Calendario su una data.
final class CalendarDateIntent extends NavigationIntent {
  const CalendarDateIntent(this.date, {this.weekView = false, this.operatorId});

  final DateTime date;
  final bool weekView;
  final String? operatorId;
}

/// Richieste di modifica, con una richiesta selezionata.
final class ChangeRequestIntent extends NavigationIntent {
  const ChangeRequestIntent({this.changeRequestId, this.pendingOnly = false});

  final String? changeRequestId;
  final bool pendingOnly;
}

/// Documenti filtrati.
final class DocumentsIntent extends NavigationIntent {
  const DocumentsIntent({this.pendingReviewOnly = false, this.ownerType});

  final bool pendingReviewOnly;
  final DocumentOwnerType? ownerType;
}

/// Sezione corrente e intenzioni di navigazione tra sezioni.
class NavigationController extends ChangeNotifier {
  AppSection _current = AppSection.dashboard;
  final Map<AppSection, NavigationIntent> _intents = {};

  AppSection get current => _current;

  void go(AppSection section, {NavigationIntent? intent}) {
    if (intent != null) _intents[section] = intent;
    if (_current == section && intent == null) return;
    _current = section;
    notifyListeners();
  }

  /// Restituisce e rimuove l'intenzione in sospeso per [section].
  NavigationIntent? takeIntent(AppSection section) => _intents.remove(section);

  bool hasIntent(AppSection section) => _intents.containsKey(section);
}

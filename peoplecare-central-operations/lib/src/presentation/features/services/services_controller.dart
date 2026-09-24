import 'dart:async';

import '../../../core/clock.dart';
import '../../../domain/domain.dart';
import '../../app_state/navigation_controller.dart';
import '../../app_state/screen_controller.dart';

/// Intervalli di date proposti nei filtri.
enum DatePreset {
  oggi('Oggi'),
  domani('Domani'),
  settimana('Questa settimana'),
  prossimi7('Prossimi 7 giorni'),
  ultimi7('Ultimi 7 giorni'),
  mese('Questo mese'),
  tutte('Tutte le date'),
  personalizzato('Personalizzato');

  const DatePreset(this.label);

  final String label;

  DateRange? rangeFor(DateTime now) {
    final today = startOfDay(now);
    return switch (this) {
      oggi => DateRange.day(today),
      domani => DateRange.day(addDays(today, 1)),
      settimana => DateRange.week(today),
      prossimi7 => DateRange(today, addDays(today, 7)),
      ultimi7 => DateRange(addDays(today, -7), addDays(today, 1)),
      mese => DateRange.month(today),
      tutte => null,
      personalizzato => null,
    };
  }
}

/// Stato della gestione servizi: filtri, ordinamento, pagina e risultati.
class ServicesController extends ScreenController {
  ServicesController({
    required PeopleCareRepositories repositories,
    required this.clock,
  }) : _repositories = repositories,
       super(
         events: repositories.events,
         topics: const {OperationalEventTopic.servizi},
       );

  final PeopleCareRepositories _repositories;
  final Clock clock;

  static const pageSize = 50;

  String search = '';
  String? facilityId;

  /// `null` = tutti, [Unassigned] o [AssignedTo].
  OperatorFilter? operator;
  String? patientId;
  String? patientLabel;
  String? serviceTypeId;
  bool customTypeOnly = false;
  DatePreset datePreset = DatePreset.settimana;
  DateRange? customRange;
  Set<ServiceStatus> statuses = {};
  Set<ServicePriority> priorities = {};
  ServiceSort sort = ServiceSort.scheduledStart;
  bool descending = false;
  int page = 1;

  PagedResult<Service> result = const PagedResult(
    items: [],
    total: 0,
    page: 1,
    pageSize: pageSize,
  );

  DateRange? get range => datePreset == DatePreset.personalizzato
      ? customRange
      : datePreset.rangeFor(clock.now());

  ServiceQuery get query => ServiceQuery(
    range: range,
    facilityIds: facilityId == null ? const {} : {facilityId!},
    operator: operator,
    patientId: patientId,
    serviceTypeId: serviceTypeId,
    customTypeOnly: customTypeOnly,
    statuses: statuses,
    priorities: priorities,
    search: search.isEmpty ? null : search,
    sort: sort,
    descending: descending,
  );

  bool get hasFilters =>
      search.isNotEmpty ||
      facilityId != null ||
      operator != null ||
      patientId != null ||
      serviceTypeId != null ||
      customTypeOnly ||
      datePreset != DatePreset.settimana ||
      statuses.isNotEmpty ||
      priorities.isNotEmpty;

  @override
  Future<void> fetch() async {
    result = await _repositories.services.searchServices(
      query,
      page: PageRequest(page: page, pageSize: pageSize),
    );
  }

  /// Tutti i risultati dei filtri correnti (per l'esportazione).
  Future<List<Service>> fetchAll() => fetchAllPages(
    (page) => _repositories.services.searchServices(query, page: page),
  );

  void _changed() {
    page = 1;
    unawaited(load());
  }

  void setSearch(String value) {
    search = value;
    _changed();
  }

  void setFacility(String? value) {
    facilityId = value;
    _changed();
  }

  void setOperator(OperatorFilter? value) {
    operator = value;
    _changed();
  }

  void setPatient(String? id, String? label) {
    patientId = id;
    patientLabel = label;
    _changed();
  }

  /// Tipologia: ID del catalogo, `'_custom'` per i personalizzati, `null`
  /// per tutte.
  void setType(String? value) {
    customTypeOnly = value == '_custom';
    serviceTypeId = customTypeOnly ? null : value;
    _changed();
  }

  void setDatePreset(DatePreset preset, {DateRange? custom}) {
    datePreset = preset;
    if (custom != null) customRange = custom;
    _changed();
  }

  void setStatuses(Set<ServiceStatus> value) {
    statuses = value;
    _changed();
  }

  void setPriorities(Set<ServicePriority> value) {
    priorities = value;
    _changed();
  }

  void setSort(ServiceSort value) {
    if (sort == value) {
      descending = !descending;
    } else {
      sort = value;
      descending = false;
    }
    _changed();
  }

  void goToPage(int value) {
    page = value;
    unawaited(load());
  }

  void clearFilters() {
    search = '';
    facilityId = null;
    operator = null;
    patientId = null;
    patientLabel = null;
    serviceTypeId = null;
    customTypeOnly = false;
    datePreset = DatePreset.settimana;
    statuses = {};
    priorities = {};
    _changed();
  }

  /// Applica i filtri richiesti da un'altra sezione.
  void applyIntent(ServicesFilterIntent intent, {String? patientLabel}) {
    search = '';
    facilityId = intent.facilityId;
    operator = intent.unassignedOnly
        ? const Unassigned()
        : (intent.operatorId == null ? null : AssignedTo(intent.operatorId!));
    patientId = intent.patientId;
    this.patientLabel = patientLabel;
    serviceTypeId = null;
    customTypeOnly = false;
    statuses = {...intent.statuses};
    priorities = {};
    if (intent.range != null) {
      datePreset = DatePreset.personalizzato;
      customRange = intent.range;
    } else {
      datePreset = intent.patientId != null || intent.operatorId != null
          ? DatePreset.tutte
          : DatePreset.settimana;
    }
    page = 1;
  }
}

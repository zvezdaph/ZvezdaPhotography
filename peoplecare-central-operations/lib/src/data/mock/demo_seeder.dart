import 'dart:math';

import '../../core/text.dart';
import '../../domain/domain.dart';
import 'demo_catalog.dart';
import 'mock_backend.dart';

/// Popola il [MockBackend] con dati DEMO realistici, costruiti attorno alla
/// data corrente: tre settimane di storico, la giornata di oggi con servizi
/// in corso e anomalie, due settimane di pianificazione futura.
///
/// Con lo stesso orologio e lo stesso seme produce sempre gli stessi dati.
class DemoDataSeeder {
  DemoDataSeeder(this.backend, {int seed = 20260924}) : _random = Random(seed);

  final MockBackend backend;
  final Random _random;

  late final DateTime _now;
  late final DateTime _today;
  final _facilityIds = <String>[];
  final _typeIdsByCode = <String, String>{};
  final _operatorIds = <String>[];
  final _operatorShift = <String, String>{};
  final _patientsByFacility = <String, List<Patient>>{};
  final _patientDirections = <String, String?>{};

  /// Servizi spostati per creare sovrapposizioni dimostrative.
  final List<String> overlapServiceIds = [];

  static const _historyDays = 21;
  static const _planningDays = 14;

  void seed() {
    _now = backend.now;
    _today = startOfDay(_now);
    backend.qualifications.addAll(demoQualifications);
    _seedFacilities();
    _seedServiceTypes();
    _seedOperators();
    _seedPatients();
    final created = _seedServices();
    _applyOperatorStatuses();
    _injectScenarios(created);
    _addHistoryNoise();
    _seedChangeRequests();
    _seedDocuments();
    _seedOperationalNotifications();
    for (final id in backend.services.keys.toList()) {
      backend.refreshServiceCounters(id);
    }
    backend.auditLog.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    backend.notifications.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _markOldNotificationsRead();
  }

  // ---------------------------------------------------------------------------
  // Utilità
  // ---------------------------------------------------------------------------

  T _pick<T>(List<T> items) => items[_random.nextInt(items.length)];

  int _between(int min, int max) => min + _random.nextInt(max - min + 1);

  bool _chance(double probability) => _random.nextDouble() < probability;

  String _colleague() =>
      _pick([demoCentralUser.name, ...demoCentralColleagues]);

  DateTime _roundTo5(DateTime value) => DateTime(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute - value.minute % 5,
  );

  /// Istante lavorativo casuale tra [from] e [to] (mai nel futuro).
  DateTime _pastInstant(DateTime from, DateTime to) {
    final upper = to.isAfter(_now) ? _now : to;
    if (!upper.isAfter(from)) {
      // Intervallo vuoto: subito dopo [from], mai nel futuro.
      final next = from.add(const Duration(minutes: 1));
      return next.isAfter(_now) ? _now : next;
    }
    final span = upper.difference(from).inMinutes;
    return from.add(Duration(minutes: _random.nextInt(max(span, 1))));
  }

  String _slug(String value) =>
      normalizeForSearch(value)
          .replaceAll(RegExp(r'[^a-z0-9]+'), '.')
          .replaceAll(RegExp(r'^\.|\.$'), '');

  // ---------------------------------------------------------------------------
  // Anagrafiche
  // ---------------------------------------------------------------------------

  void _seedFacilities() {
    for (final demo in demoFacilities) {
      final facility = Facility(
        id: backend.newId('str'),
        code: demo.code,
        name: demo.name,
        kind: FacilityKind.fromCode(demo.kind),
        address: demo.address,
        city: demo.city,
        phone: demo.phone,
        email: '${_slug(demo.name)}@demo.peoplecare.example',
      );
      backend.facilities[facility.id] = facility;
      _facilityIds.add(facility.id);
      backend.audit(
        action: AuditActions.facilityCreated,
        entityType: AuditEntityType.struttura,
        entityId: facility.id,
        entityLabel: facility.name,
        summary: 'Creata la struttura ${facility.name} (${facility.code}).',
        actorName: demoCentralColleagues.first,
        at: addDays(_today, -400),
      );
    }
    backend.nextFacilityNumber = demoFacilities.length + 1;
  }

  void _seedServiceTypes() {
    for (final demo in demoServiceTypes) {
      final type = ServiceType(
        id: backend.newId('tip'),
        code: demo.code,
        name: demo.name,
        category: demo.category,
        defaultDurationMinutes: demo.minutes,
        requiredQualifications: demo.qualifications,
        description: demo.description,
        isActive: demo.active,
      );
      backend.serviceTypes[type.id] = type;
      _typeIdsByCode[demo.code] = type.id;
    }
    backend.nextServiceTypeNumber = demoServiceTypes.length + 1;
  }

  void _seedOperators() {
    for (final demo in demoOperators) {
      final email =
          '${_slug(demo.firstName)}.${_slug(demo.lastName)}@demo.peoplecare.example';
      final created = addDays(_today, -_between(180, 900));
      final prefix = _pick(['333', '340', '347', '349', '320', '366']);
      OperatorAccount? account;
      DateTime? lastAccess;
      switch (demo.account) {
        case 'attivo':
          account = OperatorAccount(
            accountId: backend.newId('acc'),
            username: email,
            status: AccountStatus.attivo,
            linkedAt: created.add(const Duration(days: 1)),
          );
          lastAccess = _chance(0.8)
              ? _pastInstant(
                  _today.add(const Duration(hours: 6, minutes: 50)),
                  _now,
                )
              : _pastInstant(addDays(_today, -3), addDays(_today, -1));
        case 'invitato':
          account = OperatorAccount(
            accountId: backend.newId('acc'),
            username: email,
            status: AccountStatus.invitato,
            linkedAt: addDays(_today, -2),
          );
        case 'bloccato':
          account = OperatorAccount(
            accountId: backend.newId('acc'),
            username: email,
            status: AccountStatus.bloccato,
            linkedAt: created.add(const Duration(days: 1)),
          );
          lastAccess = addDays(_now, -12);
      }
      final operator = Operator(
        id: backend.newId('opr'),
        code: 'OP-${demo.number.toString().padLeft(6, '0')}',
        firstName: demo.firstName,
        lastName: demo.lastName,
        email: email,
        phone: '+39 $prefix 000 ${demo.number.toString().padLeft(4, '0')}',
        qualification: demo.qualification,
        primaryFacilityId: _facilityIds[demo.facility],
        secondaryFacilityIds: [for (final i in demo.secondary) _facilityIds[i]],
        account: account,
        lastAccessAt: lastAccess,
        createdAt: created,
        updatedAt: created,
      );
      backend.operators[operator.id] = operator;
      _operatorIds.add(operator.id);
      _operatorShift[operator.id] = demo.shift;
      backend.audit(
        action: AuditActions.operatorCreated,
        entityType: AuditEntityType.operatore,
        entityId: operator.id,
        entityLabel: operator.fullName,
        summary: 'Creato l\'operatore ${operator.fullName} (${operator.code}).',
        actorName: _colleague(),
        at: created,
      );
      if (account != null) {
        backend.audit(
          action: AuditActions.operatorAccountLinked,
          entityType: AuditEntityType.operatore,
          entityId: operator.id,
          entityLabel: operator.fullName,
          summary:
              'Collegato l\'account ${account.username} a ${operator.fullName}.',
          actorName: _colleague(),
          at: account.linkedAt ?? created,
        );
      }
    }
    backend.nextOperatorNumber =
        demoOperators.map((o) => o.number).reduce(max) + 1;
  }

  /// Sospensioni e disabilitazioni vengono applicate dopo la generazione dei
  /// servizi, così lo storico precedente resta coerente.
  void _applyOperatorStatuses() {
    for (var i = 0; i < demoOperators.length; i++) {
      final demo = demoOperators[i];
      if (demo.status == 'attivo') continue;
      final id = _operatorIds[i];
      final status = OperatorStatus.fromCode(demo.status);
      final at = status == OperatorStatus.sospeso
          ? _suspensionDate.add(const Duration(hours: 9))
          : _disableDate.add(const Duration(hours: 10));
      final current = backend.operators[id]!;
      backend.operators[id] = current.copyWith(
        status: status,
        statusReason: demo.statusReason,
        updatedAt: at,
        version: current.version + 1,
      );
      backend.audit(
        action: AuditActions.operatorStatusChanged,
        entityType: AuditEntityType.operatore,
        entityId: id,
        entityLabel: current.fullName,
        summary:
            'Stato di ${current.fullName}: ${status == OperatorStatus.sospeso ? 'Sospeso' : 'Disabilitato'} '
            '(${demo.statusReason}).',
        changes: [
          FieldChange(
            field: 'status',
            label: 'Stato',
            oldValue: 'Attivo',
            newValue: status == OperatorStatus.sospeso
                ? 'Sospeso'
                : 'Disabilitato',
          ),
        ],
        actorName: demoCentralColleagues.first,
        at: at,
      );
    }
  }

  DateTime get _suspensionDate => addDays(_today, -5);

  DateTime get _disableDate => addDays(_today, -15);

  void _seedPatients() {
    // Pazienti per struttura: domiciliari più numerosi.
    const perFacility = [8, 5, 16, 14, 5];
    var index = 0;
    for (var f = 0; f < demoFacilities.length; f++) {
      final demoFacility = demoFacilities[f];
      final facilityId = _facilityIds[f];
      final list = _patientsByFacility.putIfAbsent(facilityId, () => []);
      for (var n = 0; n < perFacility[f]; n++) {
        final firstName =
            demoPatientFirstNames[index % demoPatientFirstNames.length];
        final lastName =
            demoPatientLastNames[(index * 7 + 3) % demoPatientLastNames.length];
        final residential =
            demoFacility.kind == 'rsa' ||
            demoFacility.kind == 'comunita_alloggio';
        final String address;
        final String city;
        final String? phone;
        if (residential) {
          address =
              '${demoFacility.address} - ${demoFacility.kind == 'rsa' ? 'Nucleo ${_pick(['Glicine', 'Lavanda', 'Tiglio'])}' : 'Appartamento ${_between(1, 4)}'}, stanza ${_between(1, 24)}';
          city = demoFacility.city;
          phone = demoFacility.phone;
        } else {
          address = '${_pick(demoStreets)} ${_between(1, 120)}';
          city = _pick(demoFacility.areaCities);
          phone = _chance(0.6)
              ? '+39 035 000 ${_between(1000, 9999)}'
              : '+39 ${_pick(['335', '338', '345', '348'])} 000 ${_between(1000, 9999)}';
        }
        final patient = Patient(
          id: backend.newId('paz'),
          code: 'PZ-${(4012 + index * 7).toString().padLeft(6, '0')}',
          firstName: firstName,
          lastName: lastName,
          birthDate: DateTime(
            _between(1928, 1952),
            _between(1, 12),
            _between(1, 28),
          ),
          address: address,
          city: city,
          phone: phone,
          facilityId: facilityId,
          notes: _chance(0.45) ? _pick(demoPatientNotes) : null,
        );
        backend.patients[patient.id] = patient;
        list.add(patient);
        _patientDirections[patient.id] = residential
            ? 'Accesso dalla reception della struttura.'
            : (_chance(0.8) ? _pick(demoDirections) : null);
        index++;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Servizi
  // ---------------------------------------------------------------------------

  static const _preferredTypes = <String, List<String>>{
    'OSS': ['TS-01', 'TS-01', 'TS-02', 'TS-03', 'TS-07', 'TS-10', 'TS-11'],
    'ASA': ['TS-01', 'TS-01', 'TS-02', 'TS-02', 'TS-11', 'TS-10'],
    'Infermiere': ['TS-04', 'TS-04', 'TS-05', 'TS-05', 'TS-06', 'TS-07'],
    'Fisioterapista': ['TS-08', 'TS-08', 'TS-08', 'TS-03'],
    'Educatore professionale': ['TS-09', 'TS-09', 'TS-11'],
    'Assistente sociale': ['TS-12'],
  };

  List<({DateTime start, DateTime end})> _shiftWindows(
    DateTime day,
    String shift,
  ) {
    DateTime at(int h, int m) => atTime(day, h, m);
    return switch (shift) {
      'pomeriggio' => [(start: at(13, 30), end: at(19, 30))],
      'spezzato' => [
        (start: at(8, 0), end: at(12, 0)),
        (start: at(15, 0), end: at(19, 0)),
      ],
      _ => [(start: at(7, 30), end: at(13, 30))],
    };
  }

  bool _worksOn(DateTime day, int facilityIndex) {
    final weekday = day.weekday;
    final residential = facilityIndex == 0 || facilityIndex == 4;
    if (weekday == DateTime.sunday) return residential && _chance(0.5);
    if (weekday == DateTime.saturday) return _chance(residential ? 0.8 : 0.55);
    return _chance(0.93);
  }

  List<Service> _seedServices() {
    final drafts =
        <({ServiceDraft draft, DateTime createdAt, String author})>[];
    final firstDay = addDays(_today, -_historyDays);

    for (var d = 0; d <= _historyDays + _planningDays; d++) {
      final day = addDays(firstDay, d);
      for (var o = 0; o < _operatorIds.length; o++) {
        final operatorId = _operatorIds[o];
        final demo = demoOperators[o];
        if (demo.status == 'disabilitato' && !day.isBefore(_disableDate)) {
          continue;
        }
        if (demo.status == 'sospeso' && !day.isBefore(_suspensionDate)) {
          continue;
        }
        if (!_worksOn(day, demo.facility)) continue;
        final operator = backend.operators[operatorId]!;
        final usedPatients = <String>{};
        for (final window in _shiftWindows(day, _operatorShift[operatorId]!)) {
          var cursor = window.start.add(Duration(minutes: _between(0, 4) * 5));
          while (true) {
            final typeCode = _pick(_preferredTypes[operator.qualification]!);
            final type = backend.serviceTypes[_typeIdsByCode[typeCode]]!;
            var minutes = type.defaultDurationMinutes;
            if (minutes >= 45 && _chance(0.3)) {
              minutes += _pick([-15, 15]);
            }
            final end = cursor.add(Duration(minutes: minutes));
            if (end.isAfter(window.end)) break;
            final facilityIndex = _chance(0.85) || demo.secondary.isEmpty
                ? demo.facility
                : _pick(demo.secondary);
            final facilityId = _facilityIds[facilityIndex];
            final candidates = _patientsByFacility[facilityId]!
                .where((p) => !usedPatients.contains(p.id))
                .toList();
            if (candidates.isEmpty) break;
            final patient = _pick(candidates);
            usedPatients.add(patient.id);
            drafts.add((
              draft: _draftFor(
                type: type,
                patient: patient,
                facilityId: facilityId,
                operatorId: operatorId,
                start: cursor,
                end: end,
              ),
              createdAt: _creationTimeFor(cursor),
              author: _colleague(),
            ));
            final residential = facilityIndex == 0 || facilityIndex == 4;
            final gap = residential ? _between(1, 3) * 5 : _between(2, 6) * 5;
            cursor = end.add(Duration(minutes: gap));
          }
        }
      }
    }

    // Il servizio ancora assegnato all'operatore sospeso (anomalia da gestire).
    final suspendedIndex = demoOperators.indexWhere(
      (o) => o.status == 'sospeso',
    );
    if (suspendedIndex >= 0) {
      final operatorId = _operatorIds[suspendedIndex];
      final facilityId = _facilityIds[demoOperators[suspendedIndex].facility];
      final patient = _patientsByFacility[facilityId]!.first;
      final start = atTime(addDays(_today, 2), 9, 0);
      final type = backend.serviceTypes[_typeIdsByCode['TS-01']]!;
      drafts.add((
        draft: _draftFor(
          type: type,
          patient: patient,
          facilityId: facilityId,
          operatorId: operatorId,
          start: start,
          end: start.add(Duration(minutes: type.defaultDurationMinutes)),
        ),
        createdAt: addDays(_suspensionDate, -3),
        author: demoCentralColleagues.last,
      ));
    }

    drafts.sort(
      (a, b) => a.draft.scheduledStart.compareTo(b.draft.scheduledStart),
    );
    final created = <Service>[
      for (final item in drafts)
        backend.createService(
          item.draft,
          at: item.createdAt,
          createdBy: item.author,
          live: false,
        ),
    ];

    // Orari reali coerenti per operatore e giornata.
    final byOperatorDay = <String, List<Service>>{};
    for (final service in created) {
      final key = '${service.operatorId}|${startOfDay(service.scheduledStart)}';
      byOperatorDay.putIfAbsent(key, () => []).add(service);
    }
    for (final services in byOperatorDay.values) {
      DateTime? previousEnd;
      for (final service in services) {
        previousEnd = _applyTimeline(service, previousEnd);
      }
    }
    return created;
  }

  ServiceDraft _draftFor({
    required ServiceType type,
    required Patient patient,
    required String facilityId,
    required String? operatorId,
    required DateTime start,
    required DateTime end,
  }) {
    final r = _random.nextDouble();
    final priority = r < 0.05
        ? ServicePriority.urgente
        : r < 0.17
        ? ServicePriority.alta
        : r < 0.25
        ? ServicePriority.bassa
        : ServicePriority.normale;
    return ServiceDraft(
      kind: CatalogServiceKind(serviceTypeId: type.id, name: type.name),
      scheduledStart: start,
      scheduledEnd: end,
      patient: RegisteredServicePatient(
        patientId: patient.id,
        firstName: patient.firstName,
        lastName: patient.lastName,
      ),
      facilityId: facilityId,
      operatorId: operatorId,
      priority: priority,
      address: patient.fullAddress ?? '',
      phone: patient.phone,
      directions: _patientDirections[patient.id],
      notes: _chance(0.22) ? _pick(demoServiceNotes) : null,
    );
  }

  DateTime _creationTimeFor(DateTime start) {
    final created = addDays(start, -_between(2, 12));
    final withHour = atTime(created, _between(8, 17), _between(0, 11) * 5);
    return withHour.isAfter(_now)
        ? _now.subtract(Duration(minutes: _between(30, 600)))
        : withHour;
  }

  /// Porta ogni servizio nello stato coerente con l'ora attuale.
  ///
  /// [previousEnd] è la fine effettiva del servizio precedente dello stesso
  /// operatore nella giornata: l'operatore non può iniziare prima di averlo
  /// concluso e raggiunto il nuovo paziente. Restituisce il nuovo vincolo per
  /// il servizio successivo.
  DateTime? _applyTimeline(Service service, DateTime? previousEnd) {
    final start = service.scheduledStart;
    final end = service.scheduledEnd;
    final notifyFrom = _now.subtract(const Duration(hours: 10));

    if (start.isAfter(_now)) {
      if (_chance(0.03)) _cancel(service, beforeStart: false);
      return previousEnd;
    }
    // Servizio che (in teoria) è già iniziato o concluso.
    final r = _random.nextDouble();
    if (end.isBefore(_now) && r < 0.04) {
      final at = start.add(Duration(minutes: _between(5, 20)));
      backend.markNotExecutedFromMobile(
        service.id,
        at,
        _pick(demoNotExecutedReasons),
        live: false,
        withNotification: at.isAfter(notifyFrom),
      );
      return previousEnd;
    }
    if (end.isBefore(_now) && r < 0.085) {
      _cancel(service, beforeStart: true);
      return previousEnd;
    }
    var actualStart = start.add(Duration(minutes: _startDelayMinutes()));
    if (previousEnd != null) {
      final reachable = previousEnd.add(Duration(minutes: _between(3, 8)));
      if (reachable.isAfter(actualStart)) actualStart = reachable;
    }
    if (actualStart.isAfter(_now)) {
      // Non ancora partito: anche i successivi della giornata aspettano.
      return _now;
    }
    backend.startServiceFromMobile(
      service.id,
      actualStart,
      live: false,
      withNotification: actualStart.isAfter(notifyFrom),
    );
    final factor = 0.85 + _random.nextDouble() * 0.3;
    final actualEnd = actualStart.add(
      Duration(minutes: (service.scheduledDuration.inMinutes * factor).round()),
    );
    if (actualEnd.isAfter(_now)) return actualEnd; // ancora in corso
    backend.completeServiceFromMobile(
      service.id,
      actualEnd,
      live: false,
      withNotification: actualEnd.isAfter(notifyFrom),
    );
    return actualEnd;
  }

  int _startDelayMinutes() {
    final r = _random.nextDouble();
    if (r < 0.7) return _between(-5, 5);
    if (r < 0.9) return _between(6, 15);
    return _between(16, 35);
  }

  void _cancel(Service service, {required bool beforeStart}) {
    final reason = _pick(demoCancellationReasons);
    final latest = service.scheduledStart.subtract(const Duration(hours: 2));
    final recent = _now.subtract(Duration(hours: _between(1, 30)));
    final at = _pastInstant(
      service.createdAt,
      latest.isBefore(recent) ? latest : recent,
    );
    backend.services[service.id] = service.copyWith(
      status: ServiceStatus.annullato,
      statusReason: reason,
      updatedAt: at,
      updatedBy: service.createdBy,
      version: service.version + 1,
    );
    backend.audit(
      action: AuditActions.serviceCancelled,
      entityType: AuditEntityType.servizio,
      entityId: service.id,
      entityLabel: service.code,
      serviceId: service.id,
      actorName: service.createdBy,
      at: at,
      summary: 'Servizio annullato - motivo: $reason.',
      changes: [
        FieldChange(
          field: 'status',
          label: 'Stato',
          oldValue: service.operatorId == null ? 'Da assegnare' : 'Assegnato',
          newValue: 'Annullato',
        ),
      ],
    );
  }

  /// Scenari operativi da mostrare: ritardi, servizi da assegnare,
  /// da riprogrammare e sovrapposizioni.
  void _injectScenarios(List<Service> created) {
    Service current(Service s) => backend.services[s.id]!;
    final active = created.map(current).toList();

    // 1. Servizi che dovevano iniziare da 12-50 minuti e non sono partiti.
    final lateCandidates = active.where((s) {
      final late = _now.difference(s.scheduledStart).inMinutes;
      return late >= 12 &&
          late <= 50 &&
          s.scheduledEnd.isAfter(_now) &&
          (s.status == ServiceStatus.inCorso ||
              s.status == ServiceStatus.assegnato);
    }).toList();
    for (final service in lateCandidates.take(2)) {
      _revertToAssigned(service);
      backend.stalledServiceIds.add(service.id);
      backend.notifyLateStart(
        backend.services[service.id]!,
        at: service.scheduledStart.add(const Duration(minutes: 11)),
        live: false,
      );
    }

    // 2. Servizi futuri senza operatore.
    bool activeOperator(Service s) =>
        s.operatorId != null && backend.operators[s.operatorId]!.isAssignable;
    final futureAssigned = active
        .where(
          (s) =>
              activeOperator(s) &&
              s.status == ServiceStatus.assegnato &&
              s.scheduledStart.isAfter(_now.add(const Duration(hours: 1))) &&
              s.scheduledStart.isBefore(addDays(_today, 7)),
        )
        .toList();
    futureAssigned.shuffle(_random);
    const unassignReasons = [
      'ferie approvate',
      'malattia dell\'operatore',
      'riorganizzazione dei turni',
    ];
    for (final service in futureAssigned.take(9)) {
      final previous = service.operatorId;
      backend.services[service.id] = backend.services[service.id]!.copyWith(
        operatorId: null,
        status: ServiceStatus.daAssegnare,
        version: service.version + 1,
      );
      if (previous != null) {
        final at = _pastInstant(service.createdAt, _now);
        backend.audit(
          action: AuditActions.serviceReassigned,
          entityType: AuditEntityType.servizio,
          entityId: service.id,
          entityLabel: service.code,
          serviceId: service.id,
          actorName: _colleague(),
          at: at,
          summary:
              'Rimossa l\'assegnazione a ${backend.operatorName(previous)} '
              '(${_pick(unassignReasons)}).',
          changes: [
            FieldChange(
              field: 'operator_id',
              label: 'Operatore',
              oldValue: backend.operatorName(previous),
              newValue: 'Non assegnato',
            ),
          ],
        );
      }
    }
    _createUrgentUnassigned();

    // 3. Servizi da riprogrammare.
    const rescheduleReasons = [
      'Il familiare chiede di anticipare al mattino',
      'Paziente in attesa di dimissione ospedaliera',
      'Operatore impegnato in formazione obbligatoria',
    ];
    final toReschedule =
        active
            .where(
              (s) =>
                  activeOperator(s) &&
                  backend.services[s.id]!.status == ServiceStatus.assegnato &&
                  s.scheduledStart.isAfter(addDays(_today, 1)) &&
                  s.scheduledStart.isBefore(addDays(_today, 5)),
            )
            .toList()
          ..shuffle(_random);
    for (var i = 0; i < 3 && i < toReschedule.length; i++) {
      final service = backend.services[toReschedule[i].id]!;
      final at = _pastInstant(_now.subtract(const Duration(hours: 30)), _now);
      backend.services[service.id] = service.copyWith(
        status: ServiceStatus.daRiprogrammare,
        statusReason: rescheduleReasons[i],
        updatedAt: at,
        updatedBy: demoCentralUser.name,
        version: service.version + 1,
      );
      backend.audit(
        action: AuditActions.serviceMarkedToReschedule,
        entityType: AuditEntityType.servizio,
        entityId: service.id,
        entityLabel: service.code,
        serviceId: service.id,
        actorName: demoCentralUser.name,
        at: at,
        summary: 'Servizio da riprogrammare - motivo: ${rescheduleReasons[i]}.',
        changes: const [
          FieldChange(
            field: 'status',
            label: 'Stato',
            oldValue: 'Assegnato',
            newValue: 'Da riprogrammare',
          ),
        ],
      );
    }

    // 4. Sovrapposizioni: oggi (se c'è tempo), domani e dopodomani.
    _createOverlap(_today, minStart: _now.add(const Duration(hours: 1)));
    _createOverlap(addDays(_today, 1));
    _createOverlap(addDays(_today, 2));
  }

  void _revertToAssigned(Service service) {
    final current = backend.services[service.id]!;
    backend.services[service.id] = current.copyWith(
      status: ServiceStatus.assegnato,
      actualStart: null,
      actualEnd: null,
    );
    backend.auditLog.removeWhere(
      (entry) =>
          entry.serviceId == service.id &&
          (entry.action == AuditActions.serviceStarted ||
              entry.action == AuditActions.serviceCompleted),
    );
    backend.notifications.removeWhere(
      (n) =>
          n.serviceId == service.id &&
          (n.type == NotificationType.servizioIniziato ||
              n.type == NotificationType.servizioTerminato),
    );
  }

  void _createOverlap(DateTime day, {DateTime? minStart}) {
    final dayRange = DateRange.day(day);
    final byOperator = <String, List<Service>>{};
    for (final service in backend.services.values) {
      if (service.status != ServiceStatus.assegnato ||
          service.operatorId == null ||
          !backend.operators[service.operatorId]!.isAssignable ||
          !dayRange.contains(service.scheduledStart) ||
          backend.stalledServiceIds.contains(service.id)) {
        continue;
      }
      byOperator.putIfAbsent(service.operatorId!, () => []).add(service);
    }
    final operators = byOperator.keys.toList()..sort();
    operators.shuffle(_random);
    for (final operatorId in operators) {
      if (overlapServiceIds.any(
        (id) => backend.services[id]?.operatorId == operatorId,
      )) {
        continue;
      }
      final list = byOperator[operatorId]!
        ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
      for (var i = 0; i + 1 < list.length; i++) {
        final first = list[i];
        final second = list[i + 1];
        if (minStart != null && first.scheduledStart.isBefore(minStart)) {
          continue;
        }
        final newStart = first.scheduledEnd.subtract(
          const Duration(minutes: 30),
        );
        final duration = second.scheduledDuration;
        final previousStart = second.scheduledStart;
        backend.services[second.id] = second.copyWith(
          scheduledStart: newStart,
          scheduledEnd: newStart.add(duration),
          version: second.version + 1,
        );
        final at = _pastInstant(_now.subtract(const Duration(hours: 20)), _now);
        backend.audit(
          action: AuditActions.serviceRescheduled,
          entityType: AuditEntityType.servizio,
          entityId: second.id,
          entityLabel: second.code,
          serviceId: second.id,
          actorName: _colleague(),
          at: at,
          summary:
              'Riprogrammato dal ${formatDateTime(previousStart)} al '
              '${formatDateTime(newStart)} su richiesta della famiglia.',
          changes: [
            FieldChange(
              field: 'scheduled_start',
              label: 'Inizio programmato',
              oldValue: formatDateTime(previousStart),
              newValue: formatDateTime(newStart),
            ),
            FieldChange(
              field: 'scheduled_end',
              label: 'Fine programmata',
              oldValue: formatDateTime(second.scheduledEnd),
              newValue: formatDateTime(newStart.add(duration)),
            ),
          ],
        );
        overlapServiceIds.add(second.id);
        return;
      }
    }
  }

  void _createUrgentUnassigned() {
    final specs =
        <
          ({
            int dayOffset,
            DateTime? at,
            String type,
            int facility,
            ServicePriority priority,
            String? notes,
          })
        >[
          (
            dayOffset: 0,
            at: _roundTo5(_now.add(const Duration(minutes: 95))),
            type: 'TS-06',
            facility: 2,
            priority: ServicePriority.urgente,
            notes: 'Richiesta del medico di base: esami urgenti entro oggi.',
          ),
          (
            dayOffset: 0,
            at: _roundTo5(_now.add(const Duration(hours: 4, minutes: 10))),
            type: 'TS-05',
            facility: 3,
            priority: ServicePriority.alta,
            notes: 'Medicazione da rinnovare dopo la dimissione.',
          ),
          (
            dayOffset: 1,
            at: null,
            type: 'TS-01',
            facility: 3,
            priority: ServicePriority.normale,
            notes: null,
          ),
          (
            dayOffset: 1,
            at: null,
            type: 'TS-10',
            facility: 2,
            priority: ServicePriority.alta,
            notes: 'Visita cardiologica presso l\'ospedale alle 11:00.',
          ),
          (
            dayOffset: 2,
            at: null,
            type: 'TS-08',
            facility: 2,
            priority: ServicePriority.normale,
            notes: null,
          ),
          (
            dayOffset: 3,
            at: null,
            type: 'TS-09',
            facility: 1,
            priority: ServicePriority.bassa,
            notes: null,
          ),
        ];
    for (final spec in specs) {
      var start =
          spec.at ??
          atTime(
            addDays(_today, spec.dayOffset),
            _between(8, 16),
            _pick([0, 15, 30, 45]),
          );
      if (start.hour >= 20 || start.hour < 7) {
        start = atTime(addDays(_today, spec.dayOffset + 1), 9, 0);
      }
      final type = backend.serviceTypes[_typeIdsByCode[spec.type]]!;
      final facilityId = _facilityIds[spec.facility];
      final patient = _pick(_patientsByFacility[facilityId]!);
      final draft = _draftFor(
        type: type,
        patient: patient,
        facilityId: facilityId,
        operatorId: null,
        start: start,
        end: start.add(Duration(minutes: type.defaultDurationMinutes)),
      );
      final service = backend.createService(
        ServiceDraft(
          kind: draft.kind,
          scheduledStart: draft.scheduledStart,
          scheduledEnd: draft.scheduledEnd,
          patient: draft.patient,
          facilityId: draft.facilityId,
          priority: spec.priority,
          address: draft.address,
          phone: draft.phone,
          directions: draft.directions,
          notes: spec.notes,
        ),
        at: _now.subtract(Duration(minutes: _between(20, 240))),
        createdBy: _colleague(),
        live: false,
      );
      if (spec.priority == ServicePriority.urgente) {
        backend.notify(
          type: NotificationType.operativa,
          severity: NotificationSeverity.critica,
          title: 'Servizio urgente da assegnare',
          message:
              '${service.code} - ${type.name} per ${service.patient.fullName} '
              'alle ${formatTime(service.scheduledStart)}: nessun operatore assegnato.',
          serviceId: service.id,
          at: service.createdAt.add(const Duration(minutes: 1)),
          live: false,
        );
      }
    }
  }

  /// Qualche riassegnazione e riprogrammazione passata, coerente con lo
  /// stato finale, per rendere significative le cronologie.
  void _addHistoryNoise() {
    final candidates =
        backend.services.values
            .where(
              (s) =>
                  s.operatorId != null &&
                  s.scheduledStart.isAfter(addDays(_today, -3)) &&
                  s.createdAt.isBefore(_now.subtract(const Duration(hours: 6))),
            )
            .toList()
          ..sort((a, b) => a.code.compareTo(b.code));
    candidates.shuffle(_random);
    for (final service in candidates.take(40)) {
      final at = _pastInstant(
        service.createdAt.add(const Duration(hours: 2)),
        service.scheduledStart.subtract(const Duration(hours: 3)),
      );
      if (_chance(0.5)) {
        final previous = _pick(_operatorIds);
        if (previous == service.operatorId) continue;
        backend.audit(
          action: AuditActions.serviceReassigned,
          entityType: AuditEntityType.servizio,
          entityId: service.id,
          entityLabel: service.code,
          serviceId: service.id,
          actorName: _colleague(),
          at: at,
          summary:
              'Assegnato a ${backend.operatorName(service.operatorId)} '
              '(prima: ${backend.operatorName(previous)}).',
          changes: [
            FieldChange(
              field: 'operator_id',
              label: 'Operatore',
              oldValue: backend.operatorName(previous),
              newValue: backend.operatorName(service.operatorId),
            ),
          ],
        );
      } else {
        final previousStart = service.scheduledStart.subtract(
          Duration(minutes: _pick([-60, -30, 30, 60])),
        );
        backend.audit(
          action: AuditActions.serviceRescheduled,
          entityType: AuditEntityType.servizio,
          entityId: service.id,
          entityLabel: service.code,
          serviceId: service.id,
          actorName: _colleague(),
          at: at,
          summary:
              'Riprogrammato dal ${formatDateTime(previousStart)} al '
              '${formatDateTime(service.scheduledStart)}.',
          changes: [
            FieldChange(
              field: 'scheduled_start',
              label: 'Inizio programmato',
              oldValue: formatDateTime(previousStart),
              newValue: formatDateTime(service.scheduledStart),
            ),
          ],
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Richieste di modifica
  // ---------------------------------------------------------------------------

  void _seedChangeRequests() {
    Service? findService(bool Function(Service s) test) {
      final list = backend.services.values.where(test).toList()
        ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
      return list.isEmpty ? null : list[_random.nextInt(list.length)];
    }

    bool assignedFuture(Service s, int fromHours, int toHours) =>
        s.status == ServiceStatus.assegnato &&
        s.operatorId != null &&
        backend.operators[s.operatorId]!.isAssignable &&
        s.openChangeRequestCount == 0 &&
        s.scheduledStart.isAfter(_now.add(Duration(hours: fromHours))) &&
        s.scheduledStart.isBefore(_now.add(Duration(hours: toHours)));

    ChangeRequest? submit(
      Service? service,
      ChangeRequestReason reason,
      String message, {
      required DateTime at,
      DateTime? proposedStart,
    }) {
      if (service == null) return null;
      final request = backend.submitChangeRequestFromMobile(
        serviceId: service.id,
        reason: reason,
        message: message,
        proposedStart: proposedStart,
        proposedEnd: proposedStart?.add(service.scheduledDuration),
        at: at,
        live: false,
      );
      return request;
    }

    // In attesa.
    final morning = findService(
      (s) => assignedFuture(s, 14, 40) && s.scheduledStart.hour < 10,
    );
    submit(
      morning,
      ChangeRequestReason.problemaOrario,
      'La paziente ha una visita alle 8:30 e mi chiede di passare più tardi. '
      'Posso spostare alle 10:30?',
      at: _now.subtract(Duration(minutes: _between(15, 70))),
      proposedStart: morning == null
          ? null
          : atTime(morning.scheduledStart, 10, 30),
    );
    final overlaps = [
      for (final id in overlapServiceIds) backend.services[id]!,
    ];
    final overlap =
        overlaps
            .where((s) => isSameDay(s.scheduledStart, addDays(_today, 1)))
            .firstOrNull ??
        overlaps.lastOrNull;
    submit(
      overlap,
      ChangeRequestReason.sovrapposizione,
      'Ho due servizi sovrapposti per circa mezz\'ora: non riesco a '
      'essere in entrambi i posti.',
      at: _now.subtract(Duration(minutes: _between(40, 150))),
    );
    submit(
      findService(
        (s) => assignedFuture(s, 30, 72) && s.scheduledStart.hour >= 13,
      ),
      ChangeRequestReason.indisponibilita,
      'Ho la visita medica del lavoro nel pomeriggio, non sono disponibile '
      'dalle 14 alle 16.',
      at: _now.subtract(Duration(hours: _between(2, 5))),
    );
    submit(
      findService((s) => assignedFuture(s, 2, 12)),
      ChangeRequestReason.problemaLogistico,
      'L\'auto aziendale è in officina: con i mezzi pubblici mi servono almeno '
      '40 minuti in più per arrivare.',
      at: _now.subtract(Duration(minutes: _between(5, 30))),
    );

    // In lavorazione (con risposta della Centrale).
    final replies = [
      (
        reason: ChangeRequestReason.imprevisto,
        message:
            'Il figlio del paziente mi ha detto che sabato non saranno a casa.',
        reply:
            'Grazie, verifichiamo con la famiglia e ti aggiorniamo entro oggi.',
      ),
      (
        reason: ChangeRequestReason.altro,
        message:
            'La signora chiede di avere sempre la stessa operatrice per '
            'l\'igiene. È possibile?',
        reply: 'Ne parliamo con la coordinatrice; per ora il calendario resta invariato.',
      ),
    ];
    for (final item in replies) {
      final request = submit(
        findService((s) => assignedFuture(s, 24, 120)),
        item.reason,
        item.message,
        at: _now.subtract(Duration(hours: _between(18, 30))),
      );
      if (request == null) continue;
      final replyAt = request.createdAt.add(
        Duration(minutes: _between(10, 50)),
      );
      backend.changeRequests[request.id] = request.copyWith(
        status: ChangeRequestStatus.inLavorazione,
        updatedAt: replyAt,
        messages: [
          ChangeRequestMessage(
            id: backend.newId('msg'),
            authorKind: ActorKind.centrale,
            authorName: demoCentralUser.name,
            text: item.reply,
            sentAt: replyAt,
          ),
        ],
        version: request.version + 1,
      );
      backend.audit(
        action: AuditActions.changeRequestReplied,
        entityType: AuditEntityType.richiestaModifica,
        entityId: request.id,
        entityLabel: request.code,
        serviceId: request.serviceId,
        actorName: demoCentralUser.name,
        at: replyAt,
        summary: 'Risposta inviata a ${request.operatorName}: "${item.reply}".',
      );
    }

    // Chiuse nelle ultime due settimane.
    final closed = [
      (
        reason: ChangeRequestReason.problemaOrario,
        outcome: ChangeRequestOutcome.orarioModificato,
        message: 'Il paziente rientra dal centro diurno alle 16: posso passare alle 16:30?',
        reply: 'Ok, orario aggiornato alle 16:30.',
      ),
      (
        reason: ChangeRequestReason.indisponibilita,
        outcome: ChangeRequestOutcome.riassegnato,
        message: 'Venerdì mattina ho un esame clinico programmato.',
        reply: 'Servizio assegnato a una collega, grazie della segnalazione.',
      ),
      (
        reason: ChangeRequestReason.problemaLogistico,
        outcome: ChangeRequestOutcome.assegnazioneMantenuta,
        message: 'Strada chiusa per lavori, allungo di 10 minuti.',
        reply: 'Manteniamo l\'orario, avvisiamo noi la famiglia del possibile ritardo.',
      ),
      (
        reason: ChangeRequestReason.sovrapposizione,
        outcome: ChangeRequestOutcome.orarioModificato,
        message: 'Il servizio delle 11 si sovrappone con l\'accompagnamento.',
        reply: 'Spostato alle 12:15.',
      ),
      (
        reason: ChangeRequestReason.imprevisto,
        outcome: ChangeRequestOutcome.assegnazioneMantenuta,
        message: 'Il paziente ha la febbre, procedo comunque con l\'igiene?',
        reply: 'Sì, procedi e rileva la temperatura; avvisiamo il medico.',
      ),
      (
        reason: ChangeRequestReason.altro,
        outcome: ChangeRequestOutcome.riassegnato,
        message: 'Il paziente preferisce un operatore uomo per l\'igiene.',
        reply: 'Assegnato a un collega a partire da questa settimana.',
      ),
    ];
    for (final item in closed) {
      final service = findService(
        (s) =>
            s.status == ServiceStatus.completato &&
            s.operatorId != null &&
            s.openChangeRequestCount == 0 &&
            s.scheduledStart.isAfter(addDays(_today, -14)) &&
            s.scheduledStart.isBefore(addDays(_today, -1)),
      );
      if (service == null) continue;
      final at = service.scheduledStart.subtract(
        Duration(hours: _between(18, 40)),
      );
      final request = backend.submitChangeRequestFromMobile(
        serviceId: service.id,
        reason: item.reason,
        message: item.message,
        at: at,
        live: false,
      );
      final closedAt = at.add(Duration(minutes: _between(15, 120)));
      final closer = _colleague();
      backend.changeRequests[request.id] = request.copyWith(
        status: ChangeRequestStatus.chiusa,
        outcome: item.outcome,
        closedAt: closedAt,
        closedBy: closer,
        updatedAt: closedAt,
        messages: [
          ChangeRequestMessage(
            id: backend.newId('msg'),
            authorKind: ActorKind.centrale,
            authorName: closer,
            text: item.reply,
            sentAt: closedAt,
          ),
        ],
        version: request.version + 2,
      );
      backend.refreshServiceCounters(service.id);
      backend.audit(
        action: AuditActions.changeRequestClosed,
        entityType: AuditEntityType.richiestaModifica,
        entityId: request.id,
        entityLabel: request.code,
        serviceId: service.id,
        actorName: closer,
        at: closedAt,
        summary: 'Richiesta ${request.code} chiusa: ${item.reply}',
      );
      // Le notifiche delle richieste chiuse risultano lette.
      final index = backend.notifications.indexWhere(
        (n) => n.changeRequestId == request.id,
      );
      if (index >= 0) {
        backend.notifications[index] = backend.notifications[index].markRead(
          closedAt,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Documenti
  // ---------------------------------------------------------------------------

  void _seedDocuments() {
    // Fogli firma e foto inviati dal territorio.
    final completedRecently =
        backend.services.values
            .where(
              (s) =>
                  s.status == ServiceStatus.completato &&
                  s.actualEnd != null &&
                  s.actualEnd!.isAfter(addDays(_now, -7)),
            )
            .toList()
          ..sort((a, b) => a.actualEnd!.compareTo(b.actualEnd!));
    final selection = <Service>[
      ...completedRecently.reversed.take(4),
      ...(completedRecently.toList()..shuffle(_random)).take(10),
    ];
    final seen = <String>{};
    for (final service in selection) {
      if (!seen.add(service.id)) continue;
      final at = service.actualEnd!.add(Duration(minutes: _between(2, 12)));
      if (at.isAfter(_now)) continue;
      final isWound = service.kind.label == 'Medicazione' && _chance(0.7);
      final document = backend.receiveDocumentFromMobile(
        owner: DocumentOwner(type: DocumentOwnerType.servizio, id: service.id),
        operatorId: service.operatorId!,
        title: isWound
            ? 'Foto lesione - controllo'
            : 'Foglio firma prestazione',
        fileName: isWound
            ? 'foto_lesione_${service.code.toLowerCase()}.jpg'
            : 'foglio_firma_${service.code.toLowerCase()}.pdf',
        category: isWound
            ? DocumentCategory.fotografia
            : DocumentCategory.foglioFirma,
        sizeBytes: isWound
            ? _between(900, 2600) * 1024
            : _between(80, 420) * 1024,
        at: at,
        live: false,
      );
      // Verificati quelli più vecchi di tre ore.
      if (at.isBefore(_now.subtract(const Duration(hours: 3)))) {
        final reviewedAt = at.add(Duration(minutes: _between(20, 150)));
        backend.documents[document.id] = document.copyWith(
          reviewedAt: reviewedAt.isAfter(_now) ? _now : reviewedAt,
          reviewedBy: _colleague(),
        );
        final index = backend.notifications.indexWhere(
          (n) => n.documentId == document.id,
        );
        if (index >= 0) {
          backend.notifications[index] = backend.notifications[index].markRead(
            reviewedAt.isAfter(_now) ? _now : reviewedAt,
          );
        }
      }
    }

    // Verbali per servizi non eseguiti.
    final notExecuted =
        backend.services.values
            .where(
              (s) =>
                  s.status == ServiceStatus.nonEseguito &&
                  s.scheduledStart.isAfter(addDays(_today, -10)),
            )
            .toList()
          ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
    for (final service in notExecuted.reversed.take(3)) {
      final at = service.updatedAt.add(Duration(minutes: _between(5, 30)));
      if (at.isAfter(_now)) continue;
      final document = backend.receiveDocumentFromMobile(
        owner: DocumentOwner(type: DocumentOwnerType.servizio, id: service.id),
        operatorId: service.operatorId!,
        title: 'Verbale di mancata esecuzione',
        fileName: 'verbale_${service.code.toLowerCase()}.pdf',
        category: DocumentCategory.verbale,
        sizeBytes: _between(60, 180) * 1024,
        at: at,
        description: service.statusReason,
        live: false,
      );
      if (at.isBefore(_now.subtract(const Duration(hours: 6)))) {
        backend.documents[document.id] = document.copyWith(
          reviewedAt: at.add(const Duration(hours: 1)),
          reviewedBy: _colleague(),
        );
      }
    }

    // Prescrizioni caricate dalla Centrale sui prossimi servizi sanitari.
    final upcomingNursing =
        backend.services.values
            .where(
              (s) =>
                  s.status == ServiceStatus.assegnato &&
                  (s.kind.label == 'Prelievo ematico domiciliare' ||
                      s.kind.label == 'Somministrazione terapia') &&
                  s.scheduledStart.isAfter(_now) &&
                  s.scheduledStart.isBefore(addDays(_today, 4)),
            )
            .toList()
          ..sort((a, b) => a.scheduledStart.compareTo(b.scheduledStart));
    for (final service in upcomingNursing.take(5)) {
      _centralDocument(
        owner: DocumentOwner(type: DocumentOwnerType.servizio, id: service.id),
        title: 'Prescrizione medica',
        fileName: 'prescrizione_${service.code.toLowerCase()}.pdf',
        category: DocumentCategory.referto,
        at: _pastInstant(service.createdAt, _now),
        serviceId: service.id,
      );
    }

    // Documenti degli operatori.
    for (var i = 0; i < _operatorIds.length; i++) {
      final operator = backend.operators[_operatorIds[i]]!;
      final owner = DocumentOwner(
        type: DocumentOwnerType.operatore,
        id: operator.id,
      );
      if (i % 2 == 0) {
        _centralDocument(
          owner: owner,
          title: 'Attestato corso BLSD',
          fileName: 'attestato_blsd_${operator.code.toLowerCase()}.pdf',
          category: DocumentCategory.certificato,
          at: operator.createdAt.add(Duration(days: _between(10, 60))),
        );
      }
      if (i % 3 == 0) {
        _centralDocument(
          owner: owner,
          title: 'Attestato formazione sicurezza (D.Lgs. 81/08)',
          fileName: 'formazione_sicurezza_${operator.code.toLowerCase()}.pdf',
          category: DocumentCategory.certificato,
          at: operator.createdAt.add(Duration(days: _between(5, 30))),
        );
      }
      if (i % 5 == 0) {
        _centralDocument(
          owner: owner,
          title: 'Documento d\'identità',
          fileName: 'documento_identita_${operator.code.toLowerCase()}.pdf',
          category: DocumentCategory.documentoIdentita,
          at: operator.createdAt.add(const Duration(days: 1)),
        );
      }
    }

    // Documenti dei pazienti.
    final patients = backend.patients.values.toList();
    for (var i = 0; i < patients.length; i++) {
      final patient = patients[i];
      final owner = DocumentOwner(
        type: DocumentOwnerType.paziente,
        id: patient.id,
      );
      if (i % 2 == 0) {
        _centralDocument(
          owner: owner,
          title: 'Piano Assistenziale Individualizzato (PAI)',
          fileName: 'pai_${patient.code.toLowerCase()}.pdf',
          category: DocumentCategory.pianoAssistenziale,
          at: addDays(_now, -_between(20, 200)),
        );
      }
      if (i % 3 == 0) {
        _centralDocument(
          owner: owner,
          title: 'Consenso informato al trattamento dei dati',
          fileName: 'consenso_${patient.code.toLowerCase()}.pdf',
          category: DocumentCategory.consenso,
          at: addDays(_now, -_between(200, 400)),
        );
      }
      if (i % 7 == 0) {
        _centralDocument(
          owner: owner,
          title: 'Referto visita geriatrica',
          fileName: 'referto_geriatrico_${patient.code.toLowerCase()}.pdf',
          category: DocumentCategory.referto,
          at: addDays(_now, -_between(10, 90)),
        );
      }
    }

    // Documenti della Centrale.
    const centralDocs = [
      (
        'Procedura gestione emergenze a domicilio',
        DocumentCategory.procedura,
        120,
      ),
      ('Protocollo igiene delle mani', DocumentCategory.procedura, 300),
      ('Circolare aggiornamento DPI', DocumentCategory.procedura, 12),
      ('Turni di reperibilità del mese', DocumentCategory.altro, 3),
      ('Modulo segnalazione eventi avversi', DocumentCategory.altro, 200),
    ];
    for (final (title, category, daysAgo) in centralDocs) {
      _centralDocument(
        owner: const DocumentOwner.centrale(),
        title: title,
        fileName: '${_slug(title).replaceAll('.', '_')}.pdf',
        category: category,
        at: addDays(_now, -daysAgo),
      );
    }
  }

  void _centralDocument({
    required DocumentOwner owner,
    required String title,
    required String fileName,
    required DocumentCategory category,
    required DateTime at,
    String? serviceId,
  }) {
    final when = at.isAfter(_now) ? _now : at;
    final author = _colleague();
    final document = DocumentInfo(
      id: backend.newId('doc'),
      title: title,
      fileName: fileName,
      mimeType: 'application/pdf',
      sizeBytes: _between(90, 2400) * 1024,
      category: category,
      owner: DocumentOwner(
        type: owner.type,
        id: owner.id,
        label: backend.ownerLabel(owner.type, owner.id),
      ),
      source: DocumentSource.centrale,
      uploadedBy: author,
      uploadedAt: when,
    );
    backend.documents[document.id] = document;
    backend.audit(
      action: AuditActions.documentUploaded,
      entityType: AuditEntityType.documento,
      entityId: document.id,
      entityLabel: title,
      serviceId: serviceId,
      actorName: author,
      at: when,
      summary: 'Caricato il documento "$title" (${document.owner.label}).',
    );
  }

  // ---------------------------------------------------------------------------
  // Notifiche operative
  // ---------------------------------------------------------------------------

  void _seedOperationalNotifications() {
    if (overlapServiceIds.isNotEmpty) {
      final service = backend.services[overlapServiceIds.last]!;
      backend.notify(
        type: NotificationType.operativa,
        severity: NotificationSeverity.attenzione,
        title: 'Sovrapposizione in calendario',
        message:
            '${backend.operatorName(service.operatorId)} ha due servizi '
            'sovrapposti ${_dayLabel(service.scheduledStart)} alle '
            '${formatTime(service.scheduledStart)} (${service.code}).',
        serviceId: service.id,
        operatorId: service.operatorId,
        at: _now.subtract(Duration(minutes: _between(50, 180))),
        live: false,
      );
    }
    backend.notify(
      type: NotificationType.operativa,
      severity: NotificationSeverity.info,
      title: 'Nuova procedura disponibile',
      message:
          'È stata pubblicata la "Circolare aggiornamento DPI" nei documenti '
          'della Centrale.',
      at: addDays(_now, -12),
      live: false,
    );
  }

  String _dayLabel(DateTime day) {
    final diff = startOfDay(day).difference(_today).inDays;
    return switch (diff) {
      0 => 'oggi',
      1 => 'domani',
      _ =>
        'il ${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}',
    };
  }

  void _markOldNotificationsRead() {
    for (var i = 0; i < backend.notifications.length; i++) {
      final n = backend.notifications[i];
      if (n.isRead) continue;
      final age = _now.difference(n.createdAt);
      final stillRelevant = switch (n.type) {
        NotificationType.richiestaModifica =>
          backend.changeRequests[n.changeRequestId]?.status ==
              ChangeRequestStatus.inAttesa,
        NotificationType.documentoRicevuto =>
          backend.documents[n.documentId]?.isPendingReview ?? false,
        NotificationType.servizioProblematico => age.inHours < 3,
        NotificationType.operativa => age.inHours < 6,
        _ => age.inMinutes < 25,
      };
      if (!stillRelevant) {
        backend.notifications[i] = n.markRead(
          n.createdAt.add(
            Duration(minutes: min(age.inMinutes, _between(3, 25))),
          ),
        );
      }
    }
  }
}

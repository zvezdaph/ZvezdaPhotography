import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/domain.dart';

/// Anagrafiche di uso continuo (strutture, operatori, tipologie, qualifiche)
/// tenute in memoria e aggiornate sugli eventi in tempo reale.
///
/// Le schermate le usano per tradurre ID in nomi e popolare i filtri senza
/// interrogare ogni volta il sistema.
class ReferenceData extends ChangeNotifier {
  ReferenceData(this._repositories) {
    _subscription = _repositories.events.watchEvents().listen(_onEvent);
  }

  final PeopleCareRepositories _repositories;
  StreamSubscription<OperationalEvent>? _subscription;
  Timer? _debounce;
  bool _disposed = false;

  List<Facility> _facilities = const [];
  List<Operator> _operators = const [];
  List<ServiceType> _serviceTypes = const [];
  List<String> _qualifications = const [];
  Map<String, Facility> _facilityById = const {};
  Map<String, Operator> _operatorById = const {};
  Map<String, ServiceType> _typeById = const {};

  List<Facility> get facilities => _facilities;

  List<Facility> get activeFacilities =>
      _facilities.where((f) => f.isActive).toList();

  List<Operator> get operators => _operators;

  /// Operatori non disabilitati, ordinati per cognome.
  List<Operator> get visibleOperators =>
      _operators.where((o) => o.status != OperatorStatus.disabilitato).toList();

  List<Operator> get assignableOperators =>
      _operators.where((o) => o.isAssignable).toList();

  List<ServiceType> get serviceTypes => _serviceTypes;

  List<ServiceType> get activeServiceTypes =>
      _serviceTypes.where((t) => t.isActive).toList();

  List<String> get qualifications => _qualifications;

  Map<String, Operator> get operatorsById => _operatorById;

  Facility? facility(String? id) => id == null ? null : _facilityById[id];

  Operator? operator(String? id) => id == null ? null : _operatorById[id];

  ServiceType? serviceType(String? id) => id == null ? null : _typeById[id];

  String facilityName(String? id) =>
      facility(id)?.name ?? (id == null ? '—' : 'Struttura non disponibile');

  String operatorName(String? id) =>
      id == null ? 'Non assegnato' : (operator(id)?.fullName ?? 'Operatore');

  Future<void> load() async {
    final results = await Future.wait([
      _repositories.facilities.listFacilities(),
      _repositories.operators.listOperators(),
      _repositories.serviceTypes.listServiceTypes(),
      _repositories.operators.listQualifications(),
    ]);
    if (_disposed) return;
    _facilities = results[0] as List<Facility>;
    _operators = results[1] as List<Operator>;
    _serviceTypes = results[2] as List<ServiceType>;
    _qualifications = results[3] as List<String>;
    _facilityById = {for (final f in _facilities) f.id: f};
    _operatorById = {for (final o in _operators) o.id: o};
    _typeById = {for (final t in _serviceTypes) t.id: t};
    notifyListeners();
  }

  void _onEvent(OperationalEvent event) {
    const topics = {
      OperationalEventTopic.operatori,
      OperationalEventTopic.strutture,
      OperationalEventTopic.tipologieServizio,
    };
    if (!topics.contains(event.topic)) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(load().catchError((Object _) {}));
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

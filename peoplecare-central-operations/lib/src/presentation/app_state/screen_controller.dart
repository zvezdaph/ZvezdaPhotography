import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/domain.dart';

/// Base dei controller di schermata.
///
/// Gestisce caricamento, errore, aggiornamento automatico sugli eventi in
/// tempo reale (con debounce) e sospensione degli aggiornamenti quando la
/// schermata non è visibile.
abstract class ScreenController extends ChangeNotifier {
  ScreenController({
    required OperationalEventsRepository events,
    Set<OperationalEventTopic> topics = const {},
    this.refreshDebounce = const Duration(milliseconds: 400),
  }) : _topics = topics {
    if (topics.isNotEmpty) {
      _subscription = events.watchEvents().listen(_onEvent);
    }
  }

  final Set<OperationalEventTopic> _topics;
  final Duration refreshDebounce;
  StreamSubscription<OperationalEvent>? _subscription;
  Timer? _debounce;

  bool _loading = false;
  bool _loadedOnce = false;
  Object? _error;
  bool _active = true;
  bool _stale = false;
  bool _disposed = false;
  int _generation = 0;

  bool get isLoading => _loading;

  /// `true` dopo il primo caricamento riuscito.
  bool get hasLoaded => _loadedOnce;

  Object? get error => _error;

  bool get isDisposed => _disposed;

  /// Carica i dati della schermata (implementato dalle sottoclassi).
  @protected
  Future<void> fetch();

  /// Primo caricamento o ricarica esplicita (mostra l'indicatore).
  Future<void> load() => _run(showLoading: true);

  /// Aggiornamento in background, senza indicatore a tutta pagina.
  Future<void> refresh() => _run(showLoading: false);

  Future<void> _run({required bool showLoading}) async {
    final generation = ++_generation;
    if (showLoading || !_loadedOnce) {
      _loading = true;
      notifySafely();
    }
    try {
      await fetch();
      if (_disposed || generation != _generation) return;
      _error = null;
      _loadedOnce = true;
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _error = error;
    } finally {
      if (!_disposed && generation == _generation) {
        _loading = false;
        notifySafely();
      }
    }
  }

  /// La schermata è (in)visibile: da nascosta non ricarica, ma ricorda di
  /// farlo quando torna visibile.
  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    if (active && _stale) {
      _stale = false;
      unawaited(refresh());
    }
  }

  void _onEvent(OperationalEvent event) {
    if (!_topics.contains(event.topic)) return;
    if (!_active) {
      _stale = true;
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(refreshDebounce, () => unawaited(refresh()));
  }

  void notifySafely() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

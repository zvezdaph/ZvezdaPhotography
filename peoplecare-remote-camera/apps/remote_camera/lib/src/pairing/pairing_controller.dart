import 'dart:async';

import 'package:flutter/foundation.dart';

import 'credentials.dart';
import 'pairing_api.dart';

enum PairingPhase { idle, requesting, waiting, paired, expired, error }

typedef PairingApiFactory = PairingApi Function(Uri server);

/// Pairing flow of the phone:
/// 1. request a one-time code from the control plane;
/// 2. show code + QR while polling;
/// 3. when the Control Room claims the code, store the device token securely.
class PairingController extends ChangeNotifier {
  PairingController({
    required this.apiFactory,
    required this.credentials,
    this.onPaired,
    this.allowInsecure = false,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final PairingApiFactory apiFactory;
  final CredentialStore credentials;
  final void Function(StoredCredentials credentials)? onPaired;
  final bool allowInsecure;
  final DateTime Function() _now;

  PairingPhase phase = PairingPhase.idle;
  PairingTicket? ticket;
  Uri? server;
  String? error;
  String? warning;
  PairingApi? _api;
  Timer? _timer;
  int _generation = 0;

  Duration get remaining {
    final t = ticket;
    if (t == null) return Duration.zero;
    final left = t.expiresAt.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  Future<void> start({required String serverInput, required String deviceName, String? model, String? appVersion}) async {
    cancel();
    final generation = ++_generation;
    error = null;
    warning = null;
    try {
      server = PairingApi.normalizeServerUrl(serverInput, allowInsecure: allowInsecure);
    } on PairingException catch (e) {
      phase = PairingPhase.error;
      error = e.message;
      notifyListeners();
      return;
    }
    phase = PairingPhase.requesting;
    notifyListeners();
    final api = apiFactory(server!);
    _api = api;
    try {
      final created = await api.start(deviceName: deviceName, model: model, appVersion: appVersion);
      if (generation != _generation) return;
      ticket = created;
      phase = PairingPhase.waiting;
      notifyListeners();
      _schedulePoll(generation, created.pollInterval);
    } on PairingException catch (e) {
      if (generation != _generation) return;
      phase = PairingPhase.error;
      error = e.message;
      notifyListeners();
    }
  }

  void _schedulePoll(int generation, Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () => _poll(generation));
  }

  Future<void> _poll(int generation) async {
    final t = ticket;
    final api = _api;
    if (generation != _generation || t == null || api == null) return;
    if (_now().isAfter(t.expiresAt)) {
      phase = PairingPhase.expired;
      notifyListeners();
      return;
    }
    try {
      final result = await api.poll(t);
      if (generation != _generation) return;
      switch (result) {
        case PollPending():
          if (warning != null) {
            warning = null;
            notifyListeners();
          }
          _schedulePoll(generation, t.pollInterval);
        case PollExpired():
          phase = PairingPhase.expired;
          notifyListeners();
        case PollPaired(:final cameraId, :final cameraName, :final slot, :final deviceToken):
          final stored = StoredCredentials(
            serverUrl: server!,
            cameraId: cameraId,
            cameraName: cameraName,
            slot: slot,
            deviceToken: deviceToken,
          );
          await credentials.save(stored);
          phase = PairingPhase.paired;
          notifyListeners();
          onPaired?.call(stored);
      }
    } on PairingException catch (e) {
      if (generation != _generation) return;
      // Transient network problems: keep polling until the code expires.
      warning = e.message;
      notifyListeners();
      _schedulePoll(generation, t.pollInterval * 2);
    }
  }

  void cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    ticket = null;
    phase = PairingPhase.idle;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _api?.close();
    super.dispose();
  }
}

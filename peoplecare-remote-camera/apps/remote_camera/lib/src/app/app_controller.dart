import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../control/control_client.dart';
import '../engine/engine_bridge.dart';
import '../logging/app_logger.dart';
import '../models/camera_streaming_config.dart';
import '../models/capabilities.dart';
import '../models/engine_state.dart';
import '../models/video_settings.dart';
import '../pairing/credentials.dart';
import '../protocol/protocol.dart';
import 'command_executor.dart';
import 'settings_store.dart';
import 'status_model.dart';

enum AppPhase { loading, unpaired, paired }

typedef ControlClientFactory = ControlClient Function(StoredCredentials credentials, ControlHandlers handlers);

/// Central state of the app: pairing, native engine, control connection,
/// remote commands and telemetry.
class AppController extends ChangeNotifier implements CameraActions {
  AppController({
    required this.engine,
    required this.credentialStore,
    required this.settingsStore,
    required this.logger,
    ControlClientFactory? controlFactory,
    int Function()? clock,
  })  : _controlFactory = controlFactory ??
            ((credentials, handlers) => ControlClient(
                  serverUrl: credentials.serverUrl,
                  deviceToken: credentials.deviceToken,
                  handlers: handlers,
                )),
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final EngineBridge engine;
  final CredentialStore credentialStore;
  final SettingsStore settingsStore;
  final AppLogger logger;
  final ControlClientFactory _controlFactory;
  final int Function() _clock;
  late final CommandExecutor _executor = CommandExecutor(this);

  AppPhase phase = AppPhase.loading;
  StoredCredentials? credentials;
  AppPreferences preferences = const AppPreferences();
  CameraStreamingConfig? streamingConfig;
  String? configError;
  String? testEndpoint;
  PermissionStatus? permissions;
  Map<String, Object?> deviceInfo = const {};
  @override
  DeviceCapabilities capabilities = DeviceCapabilities.empty;
  @override
  EngineState engineState = const EngineState();
  StreamStats stats = const StreamStats();
  DeviceStatus device = const DeviceStatus();
  PreviewTexture? preview;
  LinkState controlStatus = LinkState.disconnected;
  String? cloudflareIngest;
  String? cloudflareError;
  bool cameraReady = false;
  String? cameraError;
  String? revokedMessage;
  bool screenDim = false;
  bool _preparing = false;
  bool _unpairing = false;

  ControlClient? _control;
  StreamSubscription<Map<String, Object?>>? _events;
  Timer? _telemetryTimer;
  Timer? _stateDebounce;
  String? _lastSentState;
  Completer<void>? _configWaiter;
  int? _networkId;

  @override
  VideoSettings get videoSettings => preferences.video;

  String get cameraLabel {
    final c = credentials;
    if (c == null) return 'Camera non associata';
    return c.cameraName;
  }

  bool get usingTestEndpoint => testEndpoint != null && testEndpoint!.isNotEmpty;

  // ---------------------------------------------------------------------------
  // Startup / pairing
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    preferences = await settingsStore.load();
    credentials = await credentialStore.load();
    testEndpoint = await credentialStore.loadTestEndpoint();
    final cached = await credentialStore.loadConfig();
    if (cached != null && cached.cameraId == credentials?.cameraId) streamingConfig = cached;
    try {
      deviceInfo = await engine.deviceInfo();
    } catch (e) {
      logger.warning('app', 'Informazioni dispositivo non disponibili: $e');
    }
    _events = engine.events.listen(_onEngineEvent, onError: (Object e) => logger.error('engine', 'Evento: $e'));
    try {
      _applyEngineSnapshot(await engine.getState());
    } catch (_) {
      // Engine not initialized yet.
    }
    phase = credentials == null ? AppPhase.unpaired : AppPhase.paired;
    if (credentials != null) _startControl();
    logger.info('app', 'Avvio: ${credentials == null ? 'da associare' : 'associato a ${credentials!.serverUrl.host}'}');
    notifyListeners();
  }

  Future<void> onPaired(StoredCredentials stored) async {
    credentials = stored;
    revokedMessage = null;
    phase = AppPhase.paired;
    preferences = preferences.copyWith(lastServerUrl: stored.serverUrl.toString());
    await settingsStore.save(preferences);
    logger.info('pairing', 'Associato come "${stored.cameraName}"');
    _startControl();
    notifyListeners();
  }

  Future<void> unpair({String? reason}) async {
    if (_unpairing) return;
    _unpairing = true;
    try {
      await _unpair(reason);
    } finally {
      _unpairing = false;
    }
  }

  Future<void> _unpair(String? reason) async {
    if (engineState.streaming) {
      try {
        await engine.stopStream();
      } catch (_) {}
    }
    await _control?.stop();
    _control = null;
    await credentialStore.clear();
    credentials = null;
    streamingConfig = null;
    cloudflareIngest = null;
    controlStatus = LinkState.disconnected;
    revokedMessage = reason;
    phase = AppPhase.unpaired;
    logger.warning('pairing', reason ?? 'Associazione rimossa dal telefono');
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Camera engine
  // ---------------------------------------------------------------------------

  /// Requests permissions, initializes the native engine and attaches the
  /// preview. Called by the camera screen when it becomes visible.
  Future<void> prepareCamera() async {
    if (_preparing) return;
    _preparing = true;
    cameraError = null;
    notifyListeners();
    try {
      permissions = await engine.requestPermissions();
      if (!permissions!.camera) {
        cameraError = 'Permesso fotocamera negato: concedilo nelle impostazioni per usare la camera.';
        cameraReady = false;
        return;
      }
      if (!permissions!.microphone) {
        logger.warning('camera', 'Microfono negato: verrà trasmesso audio silenzioso (Cloudflare richiede AAC)',
            code: 'microphone_denied');
      }
      await engine.setOrientationLock(preferences.video.orientation);
      final result = await engine.initialize(preferences.video);
      _applyEngineSnapshot(result);
      final constrained = preferences.video.constrainedTo(capabilities, engineState.facing);
      if (constrained != preferences.video) {
        logger.warning('camera', 'Impostazioni adattate all\'hardware: ${constrained.resolution} ${constrained.fps} fps');
        await _saveVideo(constrained);
        _applyEngineSnapshot(await engine.applySettings(constrained));
      }
      await attachPreview();
      await engine.setKeepScreenOn(preferences.keepScreenOn);
      cameraReady = true;
      _pushState(force: true);
    } on EngineException catch (e) {
      cameraError = e.message;
      logger.error('camera', e.message, code: e.code);
    } finally {
      _preparing = false;
      notifyListeners();
    }
  }

  Future<void> attachPreview() async {
    final (w, h) = preferences.video.frameSize;
    preview = await engine.attachPreview(w, h);
    notifyListeners();
  }

  Future<void> detachPreview() async {
    preview = null;
    try {
      await engine.detachPreview();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> openAppSettings() => engine.openAppSettings();

  void _applyEngineSnapshot(Map<String, Object?> snapshot) {
    final caps = snapshot['capabilities'];
    if (caps is Map) capabilities = DeviceCapabilities.fromJson(caps.cast<String, Object?>());
    final state = snapshot['state'];
    if (state is Map) engineState = EngineState.fromJson(state.cast<String, Object?>());
    final dev = snapshot['device'];
    if (dev is Map) device = DeviceStatus.fromJson(dev.cast<String, Object?>());
  }

  void _onEngineEvent(Map<String, Object?> event) {
    switch (event['type']) {
      case 'state':
        final previous = engineState;
        engineState = EngineState.fromJson(event);
        if (previous.streamStatus != engineState.streamStatus) {
          logger.info('stream', 'Stato: ${engineState.streamStatus.name}');
          _rescheduleTelemetry();
          if (engineState.streamStatus == NativeStreamStatus.live) _sendTelemetry();
        }
        _pushState();
        notifyListeners();
      case 'stats':
        stats = StreamStats.fromJson(event);
        notifyListeners();
      case 'device':
        device = DeviceStatus.fromJson(event);
        _checkNetwork(device.network, event['networkId']);
        notifyListeners();
      case 'network':
        device = device.withNetwork(NetworkInfo.fromJson(event));
        _checkNetwork(device.network, event['networkId']);
        notifyListeners();
      case 'capabilities':
        capabilities = DeviceCapabilities.fromJson(event);
        _pushState(force: true, withCapabilities: true);
        notifyListeners();
      case 'log':
        final level = LogLevel.parse(event['level']);
        final message = event['message'] as String? ?? '';
        logger.log(level, 'engine', message, code: event['code'] as String?);
        if (level != LogLevel.info) _control?.send(Outgoing.log(level.name, Redactor.redact(message)));
      default:
        break;
    }
  }

  void _checkNetwork(NetworkInfo network, Object? networkId) {
    if (networkId is! int) return;
    final changed = _networkId != null && _networkId != networkId;
    _networkId = networkId;
    if (changed) {
      logger.warning('network', 'Rete cambiata: ${network.label}. Riconnessione della regia.');
      _control?.reconnectNow();
    }
  }

  // ---------------------------------------------------------------------------
  // Control plane
  // ---------------------------------------------------------------------------

  void _startControl() {
    final c = credentials;
    if (c == null) return;
    unawaited(_control?.stop());
    _control = _controlFactory(
      c,
      ControlHandlers(
        onStatus: (status) {
          controlStatus = status;
          if (status == LinkState.connected) logger.info('regia', 'Connesso alla regia');
          notifyListeners();
        },
        onWelcome: _onWelcome,
        onCommand: (command) => unawaited(_handleCommand(command)),
        onConfig: _onConfig,
        onCloudflareStatus: (message) {
          cloudflareIngest = message['state'] as String?;
          cloudflareError = message['error'] as String?;
          notifyListeners();
        },
        onCameraInfo: (message) async {
          final name = message['cameraName'];
          final slot = message['slot'];
          if (name is String && credentials != null) {
            credentials = credentials!.copyWith(cameraName: name, slot: slot is num ? slot.toInt() : null);
            await credentialStore.save(credentials!);
            logger.info('regia', 'Nome camera aggiornato: $name');
            notifyListeners();
          }
        },
        onRevoked: () => unawaited(unpair(reason: 'Il dispositivo è stato revocato dalla regia. Associa di nuovo la camera.')),
        onUnauthorized: () =>
            unawaited(unpair(reason: 'La regia non riconosce più questo telefono (token revocato). Associa di nuovo la camera.')),
        onLog: (level, message) => logger.log(LogLevel.parse(level), 'regia', message),
      ),
    );
    _control!.start();
  }

  void _onWelcome(Map<String, Object?> welcome) {
    final name = welcome['cameraName'];
    if (name is String && credentials != null && name != credentials!.cameraName) {
      credentials = credentials!.copyWith(cameraName: name);
      unawaited(credentialStore.save(credentials!));
    }
    final cloudflare = welcome['cloudflare'];
    if (cloudflare is Map) cloudflareIngest = cloudflare['state'] as String?;
    _control?.send(Outgoing.hello(
      device: {
        'model': '${deviceInfo['manufacturer'] ?? ''} ${deviceInfo['model'] ?? ''}'.trim(),
        'appVersion': deviceInfo['appVersion'] ?? '1.0.0',
        'osVersion': 'Android ${deviceInfo['androidVersion'] ?? '?'} (API ${deviceInfo['sdkInt'] ?? '?'})',
      },
      capabilities: capabilities.toProtocolJson(),
      state: protocolState(),
    ));
    _lastSentState = null;
    _control?.send(Outgoing.configRequest());
    _sendTelemetry();
    _rescheduleTelemetry();
    notifyListeners();
  }

  void _onConfig(Map<String, Object?> message) {
    final error = message['error'];
    final raw = message['config'];
    if (raw is Map) {
      try {
        final config = CameraStreamingConfig.fromJson(raw.cast<String, Object?>());
        streamingConfig = config;
        configError = null;
        unawaited(credentialStore.saveConfig(config));
        logger.info('cloudflare', 'Configurazione ricevuta: ${config.describeRedacted()}');
      } on ConfigFormatException catch (e) {
        configError = 'Configurazione non valida: ${e.message}';
        logger.error('cloudflare', configError!);
      }
    } else if (error is Map) {
      configError = error['message'] as String? ?? 'Configurazione non disponibile';
      logger.error('cloudflare', configError!, code: error['code'] as String?);
    }
    _configWaiter?.complete();
    _configWaiter = null;
    notifyListeners();
  }

  Future<void> refreshConfig() async {
    final control = _control;
    if (control == null || !control.connected) return;
    final waiter = _configWaiter ??= Completer<void>();
    control.send(Outgoing.configRequest());
    await waiter.future.timeout(const Duration(seconds: 10), onTimeout: () {
      _configWaiter = null;
    });
  }

  Future<void> _handleCommand(DeviceCommand command) async {
    logger.info('regia', 'Comando ${command.command} da ${command.issuedBy}');
    Map<String, Object?> ackMessage;
    try {
      final result = await _executor.execute(command);
      ackMessage = Outgoing.ackCompleted(command.commandId, _jsonSafe(result), _clock());
    } on CommandFailure catch (e) {
      logger.warning('regia', 'Comando ${command.command} fallito: ${e.message}', code: e.code);
      ackMessage = Outgoing.ackFailed(command.commandId, e.code, e.message, _clock());
    } catch (e) {
      logger.error('regia', 'Comando ${command.command} in errore: $e');
      ackMessage = Outgoing.ackFailed(command.commandId, 'internal_error', e.toString(), _clock());
    }
    _control?.send(ackMessage);
    _pushState();
  }

  Map<String, Object?> _jsonSafe(Map<String, Object?> value) {
    try {
      return (jsonDecode(jsonEncode(value)) as Map).cast<String, Object?>();
    } catch (_) {
      return const {};
    }
  }

  // ---------------------------------------------------------------------------
  // Protocol state and telemetry
  // ---------------------------------------------------------------------------

  Map<String, Object?> protocolState() {
    final s = engineState;
    return {
      'cameraStatus': cameraReady ? s.cameraStatus.name : (cameraError != null ? 'error' : 'off'),
      'streamStatus': s.streamStatus.name,
      'paused': s.paused,
      'facing': s.facing,
      'zoom': s.zoom,
      'torch': s.torch,
      'autofocus': s.autofocus,
      'exposure': s.exposure,
      'videoEnabled': s.videoEnabled,
      'audioEnabled': s.audioEnabled,
      'recording': s.recording,
      'resolution': s.resolution,
      'fps': s.fps,
      'bitrateMode': s.bitrateMode,
      'targetBitrateKbps': s.targetBitrateKbps,
      'protocol': s.protocol,
      'orientation': s.orientation,
      'lastError': s.lastError == null ? null : {'code': s.lastError!.code, 'message': s.lastError!.message},
    };
  }

  Map<String, Object?> buildTelemetry() {
    final s = engineState;
    final live = s.streamStatus == NativeStreamStatus.live;
    final errors = s.recentErrors.length > 5 ? s.recentErrors.sublist(s.recentErrors.length - 5) : s.recentErrors;
    return {
      'ts': _clock(),
      'streamStatus': s.streamStatus.name,
      'network': device.network.toJson(),
      'bitrateKbps': live ? stats.bitrateKbps : 0,
      'uploadKbps': live ? stats.uploadKbps : 0,
      'queuePercent': live ? stats.queuePercent : 0,
      'fps': live ? stats.fps : 0,
      'resolution': '${s.width}x${s.height}',
      'battery': {'percent': device.batteryPercent, 'charging': device.charging, 'temperatureC': device.temperatureC},
      'thermal': device.thermal,
      'facing': s.facing,
      'zoom': s.zoom,
      'torch': s.torch,
      'micEnabled': s.audioEnabled,
      'videoEnabled': s.videoEnabled,
      'audioEnabled': s.audioEnabled,
      'uptimeSec': s.uptimeSec,
      'reconnects': s.reconnects,
      'recentErrors': errors.map((e) => {'ts': e.ts, 'code': e.code, 'message': Redactor.redact(e.message)}).toList(),
      'recording': {'active': s.recording, 'freeBytes': device.storageFreeBytes},
    };
  }

  void _sendTelemetry() {
    _control?.send(Outgoing.telemetry(buildTelemetry()));
  }

  /// Telemetry every 2 s while streaming, every 10 s otherwise: enough for the
  /// control room without loading phone and network.
  void _rescheduleTelemetry() {
    _telemetryTimer?.cancel();
    final interval = engineState.streaming ? const Duration(seconds: 2) : const Duration(seconds: 10);
    _telemetryTimer = Timer.periodic(interval, (_) => _sendTelemetry());
  }

  void _pushState({bool force = false, bool withCapabilities = false}) {
    _stateDebounce?.cancel();
    _stateDebounce = Timer(const Duration(milliseconds: 150), () {
      final state = protocolState();
      final encoded = jsonEncode(state);
      if (!force && encoded == _lastSentState) return;
      final sent = _control?.send(
            Outgoing.state(state, capabilities: withCapabilities || force ? capabilities.toProtocolJson() : null),
          ) ??
          false;
      if (sent) _lastSentState = encoded;
    });
  }

  // ---------------------------------------------------------------------------
  // CameraActions: used by the local UI and by remote commands
  // ---------------------------------------------------------------------------

  @override
  Future<Map<String, Object?>> startStream({required String source}) async {
    if (!cameraReady) {
      throw EngineException('camera_not_ready', 'Camera non pronta: apri l\'app sul telefono e concedi i permessi');
    }
    if (engineState.streaming) throw EngineException('already_streaming', 'La trasmissione è già attiva');
    if (usingTestEndpoint) {
      logger.warning('stream', 'Avvio su ENDPOINT DI TEST (non Cloudflare) richiesto da $source');
      return engine.startRawStream(testEndpoint!);
    }
    var config = streamingConfig;
    if (config == null && _control?.connected == true) {
      await refreshConfig();
      config = streamingConfig;
    }
    if (config == null) {
      throw EngineException(
        'no_config',
        configError ?? 'Configurazione Cloudflare non disponibile: collega il telefono alla regia',
      );
    }
    logger.info('stream', 'START (${config.describeRedacted()}) richiesto da $source');
    final result = await engine.startStream(
      primary: config.primary,
      fallback: config.fallback,
      autoFallback: preferences.autoFallback,
      srtLatencyMs: config.srtLatencyMs,
    );
    if (preferences.keepScreenOn) await engine.setKeepScreenOn(true);
    return result;
  }

  @override
  Future<void> stopStream({required String source}) async {
    logger.info('stream', 'STOP richiesto da $source');
    await engine.stopStream();
  }

  @override
  Future<void> pause() => engine.pause();
  @override
  Future<void> resume() => engine.resume();
  @override
  Future<void> reconnect() => engine.reconnect();
  @override
  Future<void> restartStream() => engine.restartStream();
  @override
  Future<Map<String, Object?>> switchCamera(String facing) => engine.switchCamera(facing);
  @override
  Future<Map<String, Object?>> setZoom(double zoom) => engine.setZoom(zoom);
  @override
  Future<Map<String, Object?>> zoomBy(double step) => engine.zoomBy(step);
  @override
  Future<void> setAudioEnabled(bool enabled) => engine.setAudioEnabled(enabled);
  @override
  Future<void> setVideoEnabled(bool enabled) => engine.setVideoEnabled(enabled);
  @override
  Future<Map<String, Object?>> setTorch(bool enabled) => engine.setTorch(enabled);
  @override
  Future<Map<String, Object?>> setAutoFocus(bool enabled) => engine.setAutoFocus(enabled);
  @override
  Future<Map<String, Object?>> focusAt(double x, double y) => engine.focusAt(x, y);
  @override
  Future<Map<String, Object?>> setExposure(int index) => engine.setExposure(index);

  @override
  Future<Map<String, Object?>> updateVideoSettings(VideoSettings settings) async {
    final constrained = cameraReady ? settings.constrainedTo(capabilities, engineState.facing) : settings;
    final previousOrientation = preferences.video.orientation;
    await _saveVideo(constrained);
    if (!cameraReady) return {'saved': true};
    if (constrained.orientation != previousOrientation) {
      await engine.setOrientationLock(constrained.orientation);
    }
    final result = await engine.applySettings(constrained);
    if (constrained.orientation != previousOrientation) await attachPreview();
    return {
      ...result,
      'resolution': constrained.resolution,
      'fps': constrained.fps,
      'videoBitrateKbps': constrained.videoBitrateKbps,
    };
  }

  @override
  Future<Map<String, Object?>> setBitrate(BitrateMode mode, int? kbps) async {
    final next = preferences.video.copyWith(bitrateMode: mode, videoBitrateKbps: kbps ?? preferences.video.videoBitrateKbps);
    await _saveVideo(next);
    if (!cameraReady) return {'saved': true};
    return engine.setBitrate(mode.name, kbps ?? next.videoBitrateKbps);
  }

  @override
  Future<Map<String, Object?>> setRecording(bool enabled) async {
    if (enabled && (device.storageFreeBytes ?? 0) < 1000000000) {
      final free = ((device.storageFreeBytes ?? 0) / 1e9).toStringAsFixed(1);
      throw EngineException('storage_low', 'Spazio insufficiente per la registrazione ($free GB liberi, minimo 1 GB)');
    }
    final slot = credentials?.slot ?? 0;
    final label = slot > 0 ? 'CAM${slot.toString().padLeft(2, '0')}' : 'CAM';
    return engine.setRecording(enabled, label);
  }

  Future<void> _saveVideo(VideoSettings video) async {
    preferences = preferences.copyWith(video: video);
    await settingsStore.save(preferences);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Local preferences
  // ---------------------------------------------------------------------------

  Future<void> setAutoFallback(bool value) async {
    preferences = preferences.copyWith(autoFallback: value);
    await settingsStore.save(preferences);
    notifyListeners();
  }

  Future<void> setKeepScreenOn(bool value) async {
    preferences = preferences.copyWith(keepScreenOn: value);
    await settingsStore.save(preferences);
    await engine.setKeepScreenOn(value);
    notifyListeners();
  }

  /// SCREEN DIM: minimum brightness and minimal UI; streaming is not affected.
  Future<void> setScreenDim(bool value) async {
    screenDim = value;
    await engine.setScreenBrightness(value ? 0.01 : -1);
    if (value) await engine.setKeepScreenOn(true);
    notifyListeners();
  }

  Future<void> setTestEndpoint(String? url) async {
    final value = url?.trim();
    if (value != null && value.isNotEmpty) {
      final scheme = Uri.tryParse(value)?.scheme.toLowerCase();
      if (scheme != 'srt' && scheme != 'rtmp' && scheme != 'rtmps') {
        throw EngineException('invalid_endpoint', 'Usa un URL srt://, rtmp:// o rtmps://');
      }
    }
    testEndpoint = (value == null || value.isEmpty) ? null : value;
    await credentialStore.saveTestEndpoint(testEndpoint);
    logger.warning('stream', testEndpoint == null ? 'Endpoint di test rimosso' : 'Endpoint di test impostato');
    notifyListeners();
  }

  Future<void> shutdownCamera() async {
    try {
      await engine.shutdown();
    } catch (_) {}
    cameraReady = false;
    preview = null;
    notifyListeners();
  }

  Uri? get serverUrl => credentials?.serverUrl;
  bool get allowInsecure => AppConfig.allowInsecureControlPlane || (deviceInfo['debug'] == true);

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    _stateDebounce?.cancel();
    unawaited(_events?.cancel());
    unawaited(_control?.stop());
    super.dispose();
  }
}

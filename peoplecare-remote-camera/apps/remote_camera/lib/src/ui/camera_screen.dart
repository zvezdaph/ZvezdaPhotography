import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/status_model.dart';
import '../engine/engine_bridge.dart';
import '../models/engine_state.dart';
import 'diagnostics_screen.dart';
import 'settings_sheet.dart';
import 'theme.dart';
import 'widgets/status_widgets.dart';

/// Main screen: big preview, live status, local controls.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, required this.app});

  final AppController app;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  AppController get app => widget.app;
  double? _pinchStartZoom;
  Offset? _focusMarker;
  Timer? _focusTimer;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => app.prepareCamera());
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && app.engineState.streaming) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusTimer?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !app.cameraReady) {
      unawaited(app.prepareCamera());
    }
  }

  Future<void> _run(Future<Object?> Function() action, {String? success}) async {
    try {
      await action();
      if (success != null && mounted) _toast(success, AppColors.green);
    } on EngineException catch (e) {
      if (mounted) _toast(e.message, AppColors.red);
    } catch (e) {
      if (mounted) _toast('$e', AppColors.red);
    }
  }

  void _toast(String message, Color color) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: AppColors.surfaceHigh,
        showCloseIcon: true,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: color)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        return PopScope(
          canPop: !app.engineState.streaming,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _toast('Ferma la diretta prima di uscire (la trasmissione continua in background).', AppColors.amber);
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(fit: StackFit.expand, children: [
              _preview(),
              _topBar(),
              OrientationBuilder(builder: (context, orientation) {
                return orientation == Orientation.landscape
                    ? Align(alignment: Alignment.centerRight, child: _controlPanel(vertical: true))
                    : Align(alignment: Alignment.bottomCenter, child: _controlPanel(vertical: false));
              }),
              if (app.screenDim) _dimOverlay(),
            ]),
          ),
        );
      },
    );
  }

  // --------------------------------------------------------------------------- preview

  Widget _preview() {
    final preview = app.preview;
    if (app.cameraError != null) return _cameraProblem(app.cameraError!);
    if (preview == null) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 14),
          Text('Avvio della fotocamera…', style: TextStyle(color: AppColors.muted)),
        ]),
      );
    }
    final aspect = preview.width / preview.height;
    final caps = app.capabilities.facing(app.engineState.facing);
    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: LayoutBuilder(builder: (context, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: caps?.focusPoint == true
                ? (details) {
                    final x = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                    final y = (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);
                    setState(() => _focusMarker = details.localPosition);
                    _focusTimer?.cancel();
                    _focusTimer = Timer(const Duration(milliseconds: 1200), () {
                      if (mounted) setState(() => _focusMarker = null);
                    });
                    unawaited(_run(() => app.focusAt(x, y)));
                  }
                : null,
            onScaleStart: caps?.zoomSupported == true ? (_) => _pinchStartZoom = app.engineState.zoom : null,
            onScaleUpdate: caps?.zoomSupported == true
                ? (details) {
                    final start = _pinchStartZoom ?? app.engineState.zoom;
                    final target = (start * details.scale).clamp(caps!.zoomMin, caps.zoomMax);
                    if ((target - app.engineState.zoom).abs() > 0.05) unawaited(_run(() => app.setZoom(target)));
                  }
                : null,
            child: Stack(fit: StackFit.expand, children: [
              Texture(textureId: preview.textureId, filterQuality: FilterQuality.medium),
              if (!app.engineState.videoEnabled || app.engineState.paused)
                Container(
                  color: Colors.black.withValues(alpha: 0.55),
                  alignment: Alignment.center,
                  child: Text(
                    app.engineState.paused ? 'PAUSA · in onda schermo nero e audio muto' : 'VIDEO OFF · in onda schermo nero',
                    style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5),
                  ),
                ),
              if (_focusMarker != null)
                Positioned(
                  left: _focusMarker!.dx - 32,
                  top: _focusMarker!.dy - 32,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(border: Border.all(color: AppColors.amber, width: 2), borderRadius: BorderRadius.circular(8)),
                  ),
                ),
            ]),
          );
        }),
      ),
    );
  }

  Widget _cameraProblem(String message) {
    final permissions = app.permissions;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.red)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.videocam_off, size: 48, color: AppColors.red),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
            FilledButton(onPressed: app.prepareCamera, child: const Text('RIPROVA')),
            if (permissions != null && (!permissions.camera || !permissions.microphone))
              OutlinedButton(onPressed: app.openAppSettings, child: const Text('APRI IMPOSTAZIONI')),
          ]),
        ]),
      ),
    );
  }

  // --------------------------------------------------------------------------- top bar

  Widget _topBar() {
    final s = app.engineState;
    final device = app.device;
    final battery = device.batteryPercent;
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xCC000000), Color(0x00000000)]),
        ),
        child: SafeArea(
          bottom: false,
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              LiveBadgeView(badge: StatusModel.badge(s)),
              Text(app.cameraLabel, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              StatusLight(label: 'CAMERA', light: StatusModel.cameraLight(s), detail: 'Fotocamera: ${s.cameraStatus.name}'),
              StatusLight(
                label: 'CLOUDFLARE',
                light: StatusModel.cloudflareLight(s, app.cloudflareIngest),
                detail: 'Trasmissione: ${s.streamStatus.name} · ingest Cloudflare: ${app.cloudflareIngest ?? 'n.d.'}',
              ),
              StatusLight(label: 'REGIA', light: StatusModel.controlLight(app.controlStatus), detail: 'Regia: ${app.controlStatus.name}'),
              InfoChip(
                icon: switch (device.network.type) {
                  'wifi' => Icons.wifi,
                  'cellular' => Icons.signal_cellular_alt,
                  'ethernet' => Icons.settings_ethernet,
                  'none' => Icons.signal_wifi_off,
                  _ => Icons.public,
                },
                text: device.network.label,
                color: device.network.type == 'none' ? AppColors.red : null,
              ),
              InfoChip(
                icon: device.charging ? Icons.battery_charging_full : Icons.battery_std,
                text: battery == null ? '—' : '${battery.round()}%',
                color: battery != null && battery < 20 && !device.charging ? AppColors.red : null,
              ),
              if (device.temperatureC != null)
                InfoChip(
                  icon: Icons.thermostat,
                  text: '${device.temperatureC!.toStringAsFixed(1)}°C',
                  color: device.temperatureC! > 42 ? AppColors.red : null,
                ),
              InfoChip(
                icon: s.audioEnabled ? Icons.mic : Icons.mic_off,
                text: s.audioEnabled ? 'MIC ON' : (s.microphoneAvailable ? 'MIC OFF' : 'MIC NON DISPONIBILE'),
                color: s.audioEnabled ? null : AppColors.amber,
              ),
              if (s.recording) const InfoChip(icon: Icons.fiber_manual_record, text: 'REC BACKUP', color: AppColors.red),
              if (app.usingTestEndpoint) const InfoChip(icon: Icons.science, text: 'ENDPOINT DI TEST', color: AppColors.amber),
              if (s.fallbackActive) const InfoChip(icon: Icons.swap_horiz, text: 'FALLBACK RTMPS', color: AppColors.amber),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------- controls

  Widget _controlPanel({required bool vertical}) {
    final s = app.engineState;
    final caps = app.capabilities.facing(s.facing);
    final ready = app.cameraReady;
    final streaming = s.streaming;
    final main = <Widget>[
      if (!streaming)
        _BigButton(
          label: 'START',
          color: AppColors.red,
          icon: Icons.play_arrow,
          onPressed: ready ? () => _run(() => app.startStream(source: 'locale')) : null,
        )
      else ...[
        s.paused
            ? _BigButton(label: 'RESUME', color: AppColors.green, icon: Icons.play_arrow, onPressed: () => _run(app.resume))
            : _BigButton(label: 'PAUSE', color: AppColors.amber, icon: Icons.pause, onPressed: () => _run(app.pause)),
        _BigButton(
          label: 'STOP',
          color: const Color(0xFF3A0D12),
          icon: Icons.stop,
          onPressed: () => _confirmStop(),
        ),
      ],
    ];
    final tools = <Widget>[
      _ToolButton(
        icon: Icons.cameraswitch,
        label: s.facing == 'back' ? 'FRONT' : 'BACK',
        onPressed: ready && app.capabilities.facing(s.facing == 'back' ? 'front' : 'back')?.available == true
            ? () => _run(() => app.switchCamera(s.facing == 'back' ? 'front' : 'back'))
            : null,
      ),
      _ToolButton(
        icon: s.torch ? Icons.flashlight_on : Icons.flashlight_off,
        label: 'TORCIA',
        active: s.torch,
        onPressed: ready && caps?.torch == true ? () => _run(() => app.setTorch(!s.torch)) : null,
      ),
      _ToolButton(
        icon: s.audioEnabled ? Icons.mic : Icons.mic_off,
        label: s.audioEnabled ? 'MUTE' : 'UNMUTE',
        active: !s.audioEnabled,
        onPressed: ready && s.microphoneAvailable ? () => _run(() => app.setAudioEnabled(!s.audioEnabled)) : null,
      ),
      _ToolButton(
        icon: s.videoEnabled ? Icons.videocam : Icons.videocam_off,
        label: s.videoEnabled ? 'VIDEO ON' : 'VIDEO OFF',
        active: !s.videoEnabled,
        onPressed: ready ? () => _run(() => app.setVideoEnabled(!s.videoEnabled)) : null,
      ),
      _ToolButton(
        icon: Icons.center_focus_strong,
        label: 'AUTOFOCUS',
        active: s.autofocus,
        onPressed: ready && caps?.autofocus == true ? () => _run(() => app.setAutoFocus(true), success: 'Autofocus continuo') : null,
      ),
      _ToolButton(
        icon: Icons.fiber_manual_record,
        label: s.recording ? 'BACKUP ON' : 'BACKUP OFF',
        active: s.recording,
        onPressed: ready && app.capabilities.recording ? () => _toggleRecording() : null,
      ),
      _ToolButton(icon: Icons.tune, label: 'IMPOSTA', onPressed: () => showSettingsSheet(context, app)),
      _ToolButton(icon: Icons.brightness_2, label: 'DIM', onPressed: () => _run(() => app.setScreenDim(true))),
      _ToolButton(
        icon: Icons.monitor_heart_outlined,
        label: 'DIAGNOSI',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DiagnosticsScreen(app: app))),
      ),
    ];
    final zoom = caps != null && caps.zoomSupported && ready
        ? Row(children: [
            const Icon(Icons.zoom_out, size: 18, color: AppColors.muted),
            Expanded(
              child: Slider(
                min: caps.zoomMin,
                max: caps.zoomMax,
                value: s.zoom.clamp(caps.zoomMin, caps.zoomMax),
                onChanged: (v) => unawaited(_run(() => app.setZoom(v))),
              ),
            ),
            Text('${s.zoom.toStringAsFixed(1)}×', style: const TextStyle(fontWeight: FontWeight.w800)),
          ])
        : const Text('Zoom non supportato', style: TextStyle(color: AppColors.muted, fontSize: 12));
    final telemetry = _telemetry();
    final panel = Container(
      width: vertical ? 300 : double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [for (final w in main) Expanded(child: Padding(padding: const EdgeInsets.all(3), child: w))]),
          const SizedBox(height: 8),
          zoom,
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: tools),
          const SizedBox(height: 10),
          telemetry,
        ]),
      ),
    );
    return SafeArea(child: vertical ? panel : ConstrainedBox(constraints: const BoxConstraints(maxHeight: 340), child: panel));
  }

  Widget _telemetry() {
    final s = app.engineState;
    final stats = app.stats;
    final live = s.streamStatus == NativeStreamStatus.live;
    String fmtKbps(double kbps) => kbps >= 1000 ? '${(kbps / 1000).toStringAsFixed(1)} Mbps' : '${kbps.round()} kbps';
    final uptime = Duration(seconds: s.uptimeSec);
    final hh = uptime.inHours;
    final mm = (uptime.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (uptime.inSeconds % 60).toString().padLeft(2, '0');
    Widget cell(String label, String value) => Expanded(
          child: Column(children: [
            Text(label, style: const TextStyle(fontSize: 9, color: AppColors.muted, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, fontFamily: 'monospace')),
          ]),
        );
    return Column(children: [
      Row(children: [
        cell('BITRATE', live ? fmtKbps(stats.bitrateKbps) : '—'),
        cell('FPS', live ? '${stats.fps}' : '${s.fps}'),
        cell('RISOL.', '${s.width}×${s.height}'),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        cell('UPTIME', s.uptimeSec > 0 ? '${hh > 0 ? '$hh:' : ''}$mm:$ss' : '—'),
        cell('RICONN.', '${s.reconnects}'),
        cell('PROTO', '${s.protocol.toUpperCase()}${s.bitrateMode == 'auto' ? ' · AUTO' : ''}'),
      ]),
      if (s.lastError != null && s.streamStatus != NativeStreamStatus.live) ...[
        const SizedBox(height: 8),
        Text(s.lastError!.message, style: const TextStyle(color: AppColors.amber, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    ]);
  }

  Future<void> _confirmStop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fermare la diretta?'),
        content: const Text('La trasmissione verso Cloudflare verrà chiusa.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ANNULLA')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('STOP')),
        ],
      ),
    );
    if (ok == true) await _run(() => app.stopStream(source: 'locale'));
  }

  Future<void> _toggleRecording() async {
    final s = app.engineState;
    if (s.recording) {
      await _run(() => app.setRecording(false), success: 'Registrazione salvata in Movies/PeopleCare');
      return;
    }
    final free = app.device.storageFreeBytes;
    final freeText = free == null ? 'sconosciuto' : '${(free / 1e9).toStringAsFixed(1)} GB';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrazione backup MP4'),
        content: Text('Spazio disponibile: $freeText.\nIl file viene salvato sul telefono (Movies/PeopleCare).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ANNULLA')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('REGISTRA')),
        ],
      ),
    );
    if (ok == true) await _run(() => app.setRecording(true), success: 'Registrazione backup avviata');
  }

  // --------------------------------------------------------------------------- screen dim

  Widget _dimOverlay() {
    final s = app.engineState;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: () => _run(() => app.setScreenDim(false)),
      child: Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Opacity(
          opacity: 0.55,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            LiveBadgeView(badge: StatusModel.badge(s), compact: true),
            const SizedBox(height: 10),
            Text(app.cameraLabel, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 18),
            const Text('SCREEN DIM · doppio tocco per riattivare', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({required this.label, required this.color, required this.icon, required this.onPressed});

  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: color == AppColors.amber || color == AppColors.green ? Colors.black : Colors.white,
        minimumSize: const Size(0, 64),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 26),
      label: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onPressed, this.active = false});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      width: 84,
      height: 64,
      child: Material(
        color: active ? AppColors.blue.withValues(alpha: 0.3) : Colors.white.withValues(alpha: enabled ? 0.08 : 0.03),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Opacity(
            opacity: enabled ? 1 : 0.35,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 22),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8), maxLines: 1),
            ]),
          ),
        ),
      ),
    );
  }
}

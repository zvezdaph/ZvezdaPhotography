import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../engine/engine_bridge.dart';
import '../models/video_settings.dart';
import 'theme.dart';

Future<void> showSettingsSheet(BuildContext context, AppController app) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (context) => FractionallySizedBox(heightFactor: 0.92, child: SettingsSheet(app: app)),
  );
}

/// Video format, bitrate, orientation and behaviour. Only values supported by
/// the hardware can be selected.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, required this.app});

  final AppController app;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  AppController get app => widget.app;
  double? _manualKbps;
  bool _busy = false;

  Future<void> _apply(Future<Object?> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on EngineException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final video = app.videoSettings;
        final state = app.engineState;
        final caps = app.capabilities;
        final facing = caps.facing(state.facing);
        final streaming = state.streaming;
        final kbps = _manualKbps ?? video.videoBitrateKbps.toDouble();
        final maxKbps = caps.maxBitrateKbps.clamp(VideoSettings.minBitrateKbps, VideoSettings.maxBitrateKbps).toDouble();
        return AbsorbPointer(
          absorbing: _busy,
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 30), children: [
            Row(children: [
              Text('Impostazioni video', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              if (_busy) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
            if (streaming)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'In diretta: risoluzione, FPS e orientamento riavviano l\'encoder (breve interruzione). Il bitrate cambia al volo.',
                  style: TextStyle(color: AppColors.amber),
                ),
              ),
            _title('Preset'),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final preset in VideoPreset.values)
                OutlinedButton(
                  onPressed: app.cameraReady
                      ? () => _apply(() => app.updateVideoSettings(video.applyPreset(preset)))
                      : null,
                  child: Text('${preset.label}\n${preset.resolution} · ${preset.fps} fps · ${preset.videoBitrateKbps ~/ 1000} Mbps',
                      textAlign: TextAlign.center),
                ),
            ]),
            _title('Risoluzione'),
            SegmentedButton<String>(
              segments: [
                for (final r in const ['720p', '1080p'])
                  ButtonSegment(value: r, label: Text(r.toUpperCase()), enabled: caps.resolutions.contains(r)),
              ],
              selected: {video.resolution},
              onSelectionChanged: (value) => _apply(() => app.updateVideoSettings(video.copyWith(resolution: value.first))),
            ),
            _title('FPS'),
            SegmentedButton<int>(
              segments: [
                for (final f in const [25, 30, 50, 60])
                  ButtonSegment(
                    value: f,
                    label: Text('$f'),
                    enabled: facing?.fps[video.resolution]?.contains(f) ?? false,
                  ),
              ],
              selected: {video.fps},
              onSelectionChanged: (value) => _apply(() => app.updateVideoSettings(video.copyWith(fps: value.first))),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('50/60 fps sono abilitati solo se fotocamera ed encoder li supportano.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ),
            _title('Bitrate video'),
            SegmentedButton<BitrateMode>(
              segments: const [
                ButtonSegment(value: BitrateMode.auto, label: Text('AUTO')),
                ButtonSegment(value: BitrateMode.manual, label: Text('MANUALE')),
              ],
              selected: {video.bitrateMode},
              onSelectionChanged: (value) => _apply(() => app.setBitrate(value.first, kbps.round())),
            ),
            Row(children: [
              Expanded(
                child: Slider(
                  min: VideoSettings.minBitrateKbps.toDouble(),
                  max: maxKbps,
                  divisions: ((maxKbps - VideoSettings.minBitrateKbps) / 250).round(),
                  value: kbps.clamp(VideoSettings.minBitrateKbps.toDouble(), maxKbps),
                  label: '${(kbps / 1000).toStringAsFixed(2)} Mbps',
                  onChanged: (v) => setState(() => _manualKbps = v),
                  onChangeEnd: (v) => _apply(() => app.setBitrate(video.bitrateMode, v.round())),
                ),
              ),
              SizedBox(width: 90, child: Text('${(kbps / 1000).toStringAsFixed(2)} Mbps', textAlign: TextAlign.end)),
            ]),
            Text(
              video.bitrateMode == BitrateMode.auto
                  ? 'AUTO: il bitrate si adatta alla rete fino al massimo impostato.'
                  : 'MANUALE: bitrate costante (CBR).',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            if (facing != null && facing.exposureSupported) ...[
              _title('Esposizione'),
              Row(children: [
                Expanded(
                  child: Slider(
                    min: facing.exposureMin.toDouble(),
                    max: facing.exposureMax.toDouble(),
                    divisions: (facing.exposureMax - facing.exposureMin).clamp(1, 200),
                    value: state.exposure.clamp(facing.exposureMin, facing.exposureMax).toDouble(),
                    onChanged: (v) => unawaited(_apply(() => app.setExposure(v.round()))),
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: Text('${(state.exposure * facing.exposureStep).toStringAsFixed(1)} EV', textAlign: TextAlign.end),
                ),
              ]),
            ],
            _title('Orientamento'),
            SegmentedButton<OrientationLock>(
              segments: const [
                ButtonSegment(value: OrientationLock.landscape, label: Text('LANDSCAPE LOCK'), icon: Icon(Icons.stay_current_landscape)),
                ButtonSegment(value: OrientationLock.portrait, label: Text('PORTRAIT LOCK'), icon: Icon(Icons.stay_current_portrait)),
              ],
              selected: {video.orientation},
              onSelectionChanged: (value) => _apply(() => app.updateVideoSettings(video.copyWith(orientation: value.first))),
            ),
            _title('Comportamento'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Schermo sempre acceso durante la diretta'),
              value: app.preferences.keepScreenOn,
              onChanged: (v) => _apply(() => app.setKeepScreenOn(v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fallback automatico su RTMPS'),
              subtitle: const Text('Se SRT non si connette dopo 3 tentativi (es. UDP bloccato) passa a RTMPS.'),
              value: app.preferences.autoFallback,
              onChanged: (v) => _apply(() => app.setAutoFallback(v)),
            ),
          ]),
        );
      },
    );
  }

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Text(text.toUpperCase(),
            style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w800, letterSpacing: 2, fontSize: 12)),
      );
}

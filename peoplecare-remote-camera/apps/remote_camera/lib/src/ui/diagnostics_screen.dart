import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../engine/engine_bridge.dart';
import '../logging/app_logger.dart';
import '../logging/diagnostics.dart';
import 'theme.dart';

/// Diagnostics: readable logs, full status and "COPIA REPORT DIAGNOSTICO"
/// (the report never contains tokens, passphrases or stream keys).
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key, required this.app});

  final AppController app;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  AppController get app => widget.app;
  LogLevel? _filter;
  late final TextEditingController _testEndpoint = TextEditingController(text: app.testEndpoint ?? '');

  @override
  void dispose() {
    _testEndpoint.dispose();
    super.dispose();
  }

  Map<String, Object?> _appInfo() => {
        'versione': app.deviceInfo['appVersion'],
        'debug': app.deviceInfo['debug'],
        'regia': app.serverUrl?.host ?? 'non associato',
        'camera': app.credentials == null ? 'non associato' : '${app.credentials!.cameraName} (${app.credentials!.cameraId})',
        'endpointTest': app.usingTestEndpoint ? 'ATTIVO' : 'no',
      };

  Map<String, Object?> _deviceInfo() => {
        'modello': '${app.deviceInfo['manufacturer']} ${app.deviceInfo['model']}',
        'android': '${app.deviceInfo['androidVersion']} (API ${app.deviceInfo['sdkInt']})',
        'batteria': app.device.batteryPercent == null ? 'n.d.' : '${app.device.batteryPercent!.round()}%${app.device.charging ? ' in carica' : ''}',
        'temperatura': app.device.temperatureC == null ? 'n.d.' : '${app.device.temperatureC!.toStringAsFixed(1)} °C',
        'statoTermico': app.device.thermal ?? 'n.d.',
        'rete': '${app.device.network.label}${app.device.network.metered ? ' (a consumo)' : ''}',
        'uplinkStimato': app.device.network.uplinkKbps == null ? 'n.d.' : '${app.device.network.uplinkKbps} kbps',
        'spazioLibero': app.device.storageFreeBytes == null ? 'n.d.' : '${(app.device.storageFreeBytes! / 1e9).toStringAsFixed(1)} GB',
        'permessi': app.permissions == null
            ? 'n.d.'
            : 'camera=${app.permissions!.camera} microfono=${app.permissions!.microphone} notifiche=${app.permissions!.notifications}',
      };

  Map<String, Object?> _engineInfo() {
    final s = app.engineState;
    return {
      'camera': s.cameraStatus.name,
      'stream': s.streamStatus.name,
      'pausa': s.paused,
      'protocollo': '${s.protocol}${s.fallbackActive ? ' (fallback)' : ''}',
      'formato': '${s.width}x${s.height} ${s.fps} fps',
      'bitrate': '${s.bitrateMode} target ${s.targetBitrateKbps} kbps, attuale ${s.currentVideoKbps} kbps',
      'misurato': '${app.stats.bitrateKbps.round()} kbps, coda ${app.stats.queuePercent.toStringAsFixed(0)}%',
      'lente': s.facing,
      'zoom': s.zoom.toStringAsFixed(2),
      'torcia': s.torch,
      'video/audio': '${s.videoEnabled}/${s.audioEnabled}',
      'registrazione': s.recording ? (s.recordingFile ?? 'sì') : 'no',
      'riconnessioni': s.reconnects,
      'ultimoErrore': s.lastError == null ? '—' : '${s.lastError!.code}: ${s.lastError!.message}',
      'capabilities': app.capabilities.toProtocolJson(),
    };
  }

  Map<String, Object?> _controlInfo() => {
        'regia': app.controlStatus.name,
        'ingestCloudflare': app.cloudflareIngest ?? 'n.d.',
        'erroreCloudflare': app.cloudflareError ?? '—',
        'configurazione': app.streamingConfig?.describeRedacted() ?? (app.configError ?? 'non ricevuta'),
      };

  Future<void> _copyReport() async {
    final report = DiagnosticsReport.build(
      now: DateTime.now(),
      app: _appInfo(),
      device: _deviceInfo(),
      engine: _engineInfo(),
      control: _controlInfo(),
      logs: app.logger.recent(limit: 200),
    );
    await Clipboard.setData(ClipboardData(text: report));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report diagnostico copiato (senza token, password e passphrase)')),
      );
    }
  }

  Future<void> _saveTestEndpoint(String? value) async {
    try {
      await app.setTestEndpoint(value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value == null ? 'Endpoint di test rimosso' : 'Endpoint di test salvato')));
      }
    } on EngineException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _unpair() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dissociare il telefono?'),
        content: const Text(
          'Il telefono dimenticherà la regia. Per revocare anche il token sul server usa "Revoca dispositivo" nella Control Room.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ANNULLA')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('DISSOCIA')),
        ],
      ),
    );
    if (ok == true) {
      await app.unpair(reason: 'Telefono dissociato manualmente.');
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostica'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: _copyReport,
              icon: const Icon(Icons.copy),
              label: const Text('COPIA REPORT DIAGNOSTICO'),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([app, app.logger]),
        builder: (context, _) {
          final logs = app.logger.recent(limit: 300, minLevel: _filter).reversed.toList();
          return LayoutBuilder(builder: (context, constraints) {
            final info = ListView(padding: const EdgeInsets.all(16), children: [
              _section('App', _appInfo()),
              _section('Dispositivo', _deviceInfo()),
              _section('Camera e stream', _engineInfo()..remove('capabilities')),
              _section('Regia e Cloudflare', _controlInfo()),
              const SizedBox(height: 12),
              _testEndpointCard(),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, children: [
                OutlinedButton.icon(
                  onPressed: () => app.refreshConfig(),
                  icon: const Icon(Icons.sync),
                  label: const Text('RICARICA CONFIGURAZIONE'),
                ),
                OutlinedButton.icon(
                  onPressed: () => app.shutdownCamera(),
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text('SPEGNI CAMERA'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
                  onPressed: app.credentials == null ? null : _unpair,
                  icon: const Icon(Icons.link_off),
                  label: const Text('DISSOCIA'),
                ),
              ]),
            ]);
            final logView = Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<LogLevel?>(
                  segments: const [
                    ButtonSegment(value: null, label: Text('TUTTI')),
                    ButtonSegment(value: LogLevel.warning, label: Text('WARNING+')),
                    ButtonSegment(value: LogLevel.error, label: Text('ERROR')),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (v) => setState(() => _filter = v.first),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final e = logs[index];
                    final color = switch (e.level) {
                      LogLevel.error => AppColors.red,
                      LogLevel.warning => AppColors.amber,
                      LogLevel.info => AppColors.blue,
                    };
                    return ListTile(
                      dense: true,
                      leading: Text(e.level.label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11)),
                      title: Text(e.message, style: const TextStyle(fontSize: 13)),
                      subtitle: Text('${e.time.toIso8601String().substring(11, 19)} · ${e.source}${e.code != null ? ' · ${e.code}' : ''}',
                          style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                    );
                  },
                ),
              ),
            ]);
            if (constraints.maxWidth > 900) {
              return Row(children: [Expanded(child: info), const VerticalDivider(width: 1), Expanded(child: logView)]);
            }
            return DefaultTabController(
              length: 2,
              child: Column(children: [
                const TabBar(tabs: [Tab(text: 'STATO'), Tab(text: 'LOG')]),
                Expanded(child: TabBarView(children: [info, logView])),
              ]),
            );
          });
        },
      ),
    );
  }

  Widget _section(String title, Map<String, Object?> values) {
    return Card(
      color: AppColors.surfaceHigh,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(), style: const TextStyle(color: AppColors.muted, letterSpacing: 2, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 8),
          for (final entry in values.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 130, child: Text(entry.key, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
                Expanded(child: Text('${entry.value}', style: const TextStyle(fontSize: 13, fontFamily: 'monospace'))),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _testEndpointCard() {
    return Card(
      color: AppColors.surfaceHigh,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('ENDPOINT DI TEST (OPZIONALE)',
              style: TextStyle(color: AppColors.amber, letterSpacing: 2, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 6),
          const Text(
            'Solo per collaudo senza Cloudflare (es. un server SRT locale). Se impostato, START usa questo URL invece del live input Cloudflare.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _testEndpoint,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'srt://192.168.1.10:9000?streamid=test'),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 10, children: [
            FilledButton(onPressed: () => _saveTestEndpoint(_testEndpoint.text), child: const Text('SALVA')),
            OutlinedButton(
              onPressed: () {
                _testEndpoint.clear();
                _saveTestEndpoint(null);
              },
              child: const Text('RIMUOVI'),
            ),
          ]),
        ]),
      ),
    );
  }
}

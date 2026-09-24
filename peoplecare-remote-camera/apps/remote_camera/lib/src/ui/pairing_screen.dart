import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../config/app_config.dart';
import '../pairing/pairing_api.dart';
import '../pairing/pairing_controller.dart';
import 'theme.dart';
import 'widgets/qr_code_view.dart';

/// First start: "ASSOCIA ALLA REGIA" — shows a one-time code and its QR code.
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key, required this.app, required this.pairing});

  final AppController app;
  final PairingController pairing;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  late final TextEditingController _server;
  late final TextEditingController _name;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    final prefs = widget.app.preferences;
    final defaultServer = prefs.lastServerUrl ?? AppConfig.defaultControlPlaneUrl;
    _server = TextEditingController(text: defaultServer);
    final model = '${widget.app.deviceInfo['model'] ?? 'Android'}';
    _name = TextEditingController(text: prefs.deviceName ?? model);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.pairing.phase == PairingPhase.waiting && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _server.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    FocusScope.of(context).unfocus();
    await widget.pairing.start(
      serverInput: _server.text,
      deviceName: _name.text.trim().isEmpty ? 'Android' : _name.text.trim(),
      model: '${widget.app.deviceInfo['manufacturer'] ?? ''} ${widget.app.deviceInfo['model'] ?? ''}'.trim(),
      appVersion: widget.app.deviceInfo['appVersion'] as String?,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.pairing,
          builder: (context, _) {
            final p = widget.pairing;
            return LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth > 760;
              final form = _form(context, p);
              final code = _codePanel(context, p);
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                  child: wide
                      ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                          Expanded(child: form),
                          const SizedBox(width: 32),
                          Expanded(child: code),
                        ])
                      : Column(children: [form, const SizedBox(height: 24), code]),
                ),
              );
            });
          },
        ),
      ),
    );
  }

  Widget _form(BuildContext context, PairingController p) {
    final busy = p.phase == PairingPhase.requesting || p.phase == PairingPhase.waiting;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Container(
          width: 14,
          height: 14,
          decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Text('PeopleCare Remote Camera', style: Theme.of(context).textTheme.titleLarge),
      ]),
      const SizedBox(height: 18),
      Text('ASSOCIA ALLA REGIA', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 30)),
      const SizedBox(height: 8),
      const Text(
        'Genera un codice e inseriscilo nella Control Room (Aggiungi camera). '
        'Il telefono ricorderà la regia per i prossimi avvii.',
        style: TextStyle(color: AppColors.muted),
      ),
      if (widget.app.revokedMessage != null) ...[
        const SizedBox(height: 16),
        _Banner(text: widget.app.revokedMessage!, color: AppColors.amber),
      ],
      const SizedBox(height: 22),
      TextField(
        controller: _server,
        enabled: !busy,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'Indirizzo della regia',
          hintText: 'https://peoplecare-remote-camera.<account>.workers.dev',
          prefixIcon: Icon(Icons.cloud_outlined),
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _name,
        enabled: !busy,
        maxLength: 64,
        decoration: const InputDecoration(labelText: 'Nome del telefono', prefixIcon: Icon(Icons.smartphone)),
      ),
      const SizedBox(height: 8),
      if (p.error != null) _Banner(text: p.error!, color: AppColors.red),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: busy ? null : _start,
        icon: const Icon(Icons.link),
        label: Text(p.phase == PairingPhase.expired ? 'GENERA NUOVO CODICE' : 'GENERA CODICE'),
      ),
      if (busy) ...[
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => setState(() => widget.pairing.cancel()),
          child: const Text('ANNULLA'),
        ),
      ],
    ]);
  }

  Widget _codePanel(BuildContext context, PairingController p) {
    final ticket = p.ticket;
    Widget content;
    switch (p.phase) {
      case PairingPhase.requesting:
        content = const Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Richiesta del codice alla regia…'),
        ]);
      case PairingPhase.waiting when ticket != null:
        final remaining = p.remaining;
        final mm = remaining.inMinutes.toString().padLeft(2, '0');
        final ss = (remaining.inSeconds % 60).toString().padLeft(2, '0');
        content = Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('CODICE DISPOSITIVO', style: TextStyle(color: AppColors.muted, letterSpacing: 3, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          SelectableText(
            ticket.code,
            style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900, letterSpacing: 6, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 16),
          QrCodeView(data: pairingQrPayload(ticket.code, p.server!), size: 190),
          const SizedBox(height: 16),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text('In attesa della regia · scade tra $mm:$ss'),
          ]),
          if (p.warning != null) ...[
            const SizedBox(height: 10),
            Text(p.warning!, style: const TextStyle(color: AppColors.amber)),
          ],
        ]);
      case PairingPhase.expired:
        content = const Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.timer_off, size: 48, color: AppColors.amber),
          SizedBox(height: 12),
          Text('Codice scaduto: generane uno nuovo.'),
        ]);
      case PairingPhase.paired:
        content = const Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle, size: 56, color: AppColors.green),
          SizedBox(height: 12),
          Text('Associato alla regia!'),
        ]);
      default:
        content = const Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.qr_code_2, size: 64, color: AppColors.muted),
          SizedBox(height: 12),
          Text('Il codice e il QR appariranno qui.', style: TextStyle(color: AppColors.muted)),
        ]);
    }
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Center(child: content),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(text, style: TextStyle(color: color)),
    );
  }
}

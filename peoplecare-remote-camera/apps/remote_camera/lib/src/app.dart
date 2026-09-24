import 'package:flutter/material.dart';

import 'app/app_controller.dart';
import 'pairing/pairing_api.dart';
import 'pairing/pairing_controller.dart';
import 'ui/camera_screen.dart';
import 'ui/pairing_screen.dart';
import 'ui/theme.dart';

class RemoteCameraApp extends StatefulWidget {
  const RemoteCameraApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<RemoteCameraApp> createState() => _RemoteCameraAppState();
}

class _RemoteCameraAppState extends State<RemoteCameraApp> {
  late final PairingController _pairing = PairingController(
    apiFactory: (server) => PairingApi(server, allowInsecure: widget.controller.allowInsecure),
    credentials: widget.controller.credentialStore,
    allowInsecure: widget.controller.allowInsecure,
    onPaired: (credentials) => widget.controller.onPaired(credentials),
  );

  @override
  void dispose() {
    _pairing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PeopleCare Remote Camera',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(),
      themeMode: ThemeMode.dark,
      home: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          switch (widget.controller.phase) {
            case AppPhase.loading:
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            case AppPhase.unpaired:
              return PairingScreen(app: widget.controller, pairing: _pairing);
            case AppPhase.paired:
              return CameraScreen(app: widget.controller);
          }
        },
      ),
    );
  }
}

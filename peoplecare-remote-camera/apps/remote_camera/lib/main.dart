import 'dart:async';

import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/app/app_controller.dart';
import 'src/app/settings_store.dart';
import 'src/engine/engine_bridge.dart';
import 'src/logging/app_logger.dart';
import 'src/pairing/credentials.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final logger = AppLogger();
  FlutterError.onError = (details) {
    logger.error('flutter', details.exceptionAsString());
    FlutterError.presentError(details);
  };
  final controller = AppController(
    engine: MethodChannelEngineBridge(),
    credentialStore: CredentialStore(FlutterSecretStore()),
    settingsStore: SharedPrefsSettingsStore(),
    logger: logger,
  );
  runZonedGuarded(
    () {
      runApp(RemoteCameraApp(controller: controller));
      unawaited(controller.init());
    },
    (error, stack) => logger.error('app', 'Errore non gestito: $error'),
  );
}

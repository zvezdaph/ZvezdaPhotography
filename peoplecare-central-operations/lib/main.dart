import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'src/app/app.dart';
import 'src/app/app_config.dart';
import 'src/app/bootstrap.dart';

/// PeopleCare Central Operations - pannello operativo della Centrale
/// Operativa PeopleCare (Flutter Desktop per Windows).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it_IT');
  Intl.defaultLocale = 'it_IT';
  final config = AppConfig.fromEnvironment();
  runApp(PeopleCareBootstrap(load: () => createAppDependencies(config)));
}

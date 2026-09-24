import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peoplecare_central_operations/src/presentation/app_state/navigation_controller.dart';

import '../support/test_support.dart';

void main() {
  setUpAll(initItalianFormatting);

  testWidgets('avvio in modalità demo e navigazione in tutte le sezioni', (
    tester,
  ) async {
    final deps = await createTestDependencies();
    await pumpApp(tester, deps);

    expect(find.text('Buongiorno, Laura'), findsOneWidget);
    expect(find.text('MODALITÀ DEMO'), findsOneWidget);

    for (final section in AppSection.values) {
      deps.navigation.go(section);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: section.title);
      expect(find.text(section.title), findsWidgets, reason: section.title);
    }
    await disposeApp(tester, deps);
  });

  testWidgets('scorciatoie da tastiera per le sezioni', (tester) async {
    final deps = await createTestDependencies();
    await pumpApp(tester, deps);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    expect(deps.navigation.current, AppSection.services);
    expect(find.text('Gestione servizi'), findsOneWidget);

    await disposeApp(tester, deps);
  });

  testWidgets('nuovo servizio: i campi obbligatori sono verificati', (
    tester,
  ) async {
    final deps = await createTestDependencies();
    await pumpApp(tester, deps);

    await tester.tap(find.widgetWithText(FilledButton, 'Nuovo servizio').first);
    await settle(tester);
    expect(find.text('I campi con * sono obbligatori.'), findsOneWidget);

    await tester.tap(find.text('Crea servizio'));
    await settle(tester);
    expect(find.text('Scegli la tipologia dal catalogo.'), findsOneWidget);
    expect(find.text('Seleziona la struttura.'), findsOneWidget);
    expect(find.text('Indica l\'indirizzo.'), findsOneWidget);

    await tester.tap(find.text('Annulla'));
    await settle(tester);
    expect(find.text('I campi con * sono obbligatori.'), findsNothing);

    await disposeApp(tester, deps);
  });
}

import 'package:flutter/widgets.dart';

/// Indica a una schermata se è quella visibile.
class SectionActivity extends InheritedWidget {
  const SectionActivity({
    super.key,
    required this.active,
    required super.child,
  });

  final bool active;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SectionActivity>()?.active ??
      true;

  @override
  bool updateShouldNotify(SectionActivity oldWidget) =>
      active != oldWidget.active;
}

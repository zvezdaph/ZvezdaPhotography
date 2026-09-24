import 'package:flutter/material.dart';

import '../../../core/date_range.dart';
import '../../theme/app_palette.dart';
import '../formatters.dart';

/// Campo data con calendario (in italiano).
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.enabled = true,
    this.errorText,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool enabled;
  final String? errorText;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final initial = value ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate ?? DateTime(now.year - 2),
      lastDate: lastDate ?? DateTime(now.year + 2, 12, 31),
      locale: const Locale('it', 'IT'),
      helpText: label,
      cancelText: 'Annulla',
      confirmText: 'OK',
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => _pick(context) : null,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        isEmpty: value == null,
        decoration: InputDecoration(
          labelText: label,
          enabled: enabled,
          errorText: errorText,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(
          value == null
              ? ''
              : '${Fmt.date(value!)}  ·  ${Fmt.capitalize(Fmt.weekdayShort(value!))}',
          style: const TextStyle(fontSize: 14.5),
        ),
      ),
    );
  }
}

/// Campo orario "HH:mm": accetta anche "8", "830", "8.30" e offre l'elenco
/// dei quarti d'ora.
class TimeField extends StatefulWidget {
  const TimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.errorText,
    this.firstMinute = 6 * 60,
    this.lastMinute = 22 * 60,
  });

  final String label;

  /// Minuti dalla mezzanotte.
  final int? value;
  final ValueChanged<int?> onChanged;
  final bool enabled;
  final String? errorText;
  final int firstMinute;
  final int lastMinute;

  @override
  State<TimeField> createState() => _TimeFieldState();
}

class _TimeFieldState extends State<TimeField> {
  late final _controller = TextEditingController(text: _format(widget.value));
  final _focus = FocusNode();
  bool _invalid = false;

  static String _format(int? minutes) =>
      minutes == null ? '' : Fmt.minutesOfDay(minutes);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _normalize();
    });
  }

  @override
  void didUpdateWidget(TimeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && !_focus.hasFocus) {
      _controller.text = _format(widget.value);
      _invalid = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _normalize() {
    final parsed = parseTimeOfDay(_controller.text);
    setState(() => _invalid = _controller.text.isNotEmpty && parsed == null);
    if (parsed != null) _controller.text = _format(parsed);
    widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final options = [
      for (var m = widget.firstMinute; m <= widget.lastMinute; m += 15) m,
    ];
    return TextField(
      controller: _controller,
      focusNode: _focus,
      enabled: widget.enabled,
      keyboardType: TextInputType.datetime,
      onChanged: (text) {
        final parsed = parseTimeOfDay(text);
        if (parsed != null) widget.onChanged(parsed);
      },
      onSubmitted: (_) => _normalize(),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: 'hh:mm',
        errorText: _invalid ? 'Orario non valido' : widget.errorText,
        suffixIcon: MenuAnchor(
          menuChildren: [
            SizedBox(
              height: 280,
              width: 120,
              child: ListView(
                children: [
                  for (final minutes in options)
                    MenuItemButton(
                      onPressed: () {
                        _controller.text = _format(minutes);
                        setState(() => _invalid = false);
                        widget.onChanged(minutes);
                      },
                      child: Text(
                        Fmt.minutesOfDay(minutes),
                        style: TextStyle(
                          fontWeight: minutes == widget.value
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          builder: (context, controller, _) => IconButton(
            tooltip: 'Scegli orario',
            icon: const Icon(Icons.schedule, size: 18),
            onPressed: widget.enabled
                ? () =>
                      controller.isOpen ? controller.close() : controller.open()
                : null,
          ),
        ),
      ),
    );
  }
}

/// Interpreta un orario digitato: "8", "08", "830", "8:30", "8.30", "08:30".
/// Restituisce i minuti dalla mezzanotte o `null`.
int? parseTimeOfDay(String text) {
  final clean = text.trim().replaceAll('.', ':').replaceAll(',', ':');
  if (clean.isEmpty) return null;
  int? hours;
  int? minutes;
  if (clean.contains(':')) {
    final parts = clean.split(':');
    if (parts.length != 2) return null;
    hours = int.tryParse(parts[0]);
    minutes = int.tryParse(parts[1].isEmpty ? '0' : parts[1]);
  } else if (RegExp(r'^\d{1,2}$').hasMatch(clean)) {
    hours = int.tryParse(clean);
    minutes = 0;
  } else if (RegExp(r'^\d{3,4}$').hasMatch(clean)) {
    hours = int.tryParse(clean.substring(0, clean.length - 2));
    minutes = int.tryParse(clean.substring(clean.length - 2));
  }
  if (hours == null || minutes == null) return null;
  if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) return null;
  return hours * 60 + minutes;
}

/// Combina una data e i minuti dalla mezzanotte.
DateTime combineDateAndMinutes(DateTime day, int minutes) =>
    atTime(day, minutes ~/ 60, minutes % 60);

/// Etichetta di campo con asterisco per i campi obbligatori.
String requiredLabel(String label) => '$label *';

/// Segmento selezionabile in stile "scheda" (usato nei form).
class ChoiceSegment<T> extends StatelessWidget {
  const ChoiceSegment({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<(T, String, IconData?)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<T>(
      showSelectedIcon: false,
      segments: [
        for (final (option, label, icon) in options)
          ButtonSegment<T>(
            value: option,
            label: Text(label),
            icon: icon == null ? null : Icon(icon, size: 17),
          ),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
      style: ButtonStyle(
        side: WidgetStatePropertyAll(
          BorderSide(color: context.palette.borderStrong),
        ),
      ),
    );
  }
}

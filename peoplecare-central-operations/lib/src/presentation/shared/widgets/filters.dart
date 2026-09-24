import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';

/// Opzione di un filtro.
class FilterOption<T> {
  const FilterOption(this.value, this.label, {this.icon, this.color});

  final T value;
  final String label;
  final IconData? icon;
  final Color? color;
}

/// Pulsante di filtro "Etichetta: valore ▾".
class FilterButton extends StatelessWidget {
  const FilterButton({
    super.key,
    required this.label,
    required this.valueLabel,
    required this.active,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final String valueLabel;
  final bool active;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: active ? primary.withValues(alpha: 0.09) : palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: active ? primary.withValues(alpha: 0.6) : palette.borderStrong,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 17,
                  color: active ? primary : palette.textSecondary,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                '$label: ',
                style: TextStyle(color: palette.textSecondary, fontSize: 13.5),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: Text(
                  valueLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? primary : palette.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_drop_down,
                size: 20,
                color: palette.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Filtro a scelta singola (con voce "Tutti").
class FilterMenu<T> extends StatelessWidget {
  const FilterMenu({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.allLabel = 'Tutti',
    this.icon,
    this.allowAll = true,
  });

  final String label;
  final List<FilterOption<T>> options;
  final T? value;
  final ValueChanged<T?> onChanged;
  final String allLabel;
  final IconData? icon;
  final bool allowAll;

  @override
  Widget build(BuildContext context) {
    final selected = options.where((o) => o.value == value).firstOrNull;
    return MenuAnchor(
      menuChildren: [
        if (allowAll)
          MenuItemButton(
            leadingIcon: _check(context, value == null),
            onPressed: () => onChanged(null),
            child: Text(allLabel),
          ),
        for (final option in options)
          MenuItemButton(
            leadingIcon: _check(context, option.value == value),
            trailingIcon: option.icon == null
                ? null
                : Icon(option.icon, size: 16, color: option.color),
            onPressed: () => onChanged(option.value),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(option.label, overflow: TextOverflow.ellipsis),
            ),
          ),
      ],
      builder: (context, controller, _) => FilterButton(
        label: label,
        valueLabel: selected?.label ?? allLabel,
        active: value != null && allowAll,
        icon: icon,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// Filtro a scelta multipla (il menu resta aperto mentre si selezionano le
/// voci).
class MultiFilterMenu<T> extends StatelessWidget {
  const MultiFilterMenu({
    super.key,
    required this.label,
    required this.options,
    required this.values,
    required this.onChanged,
    this.allLabel = 'Tutti',
    this.icon,
  });

  final String label;
  final List<FilterOption<T>> options;
  final Set<T> values;
  final ValueChanged<Set<T>> onChanged;
  final String allLabel;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final selected = options.where((o) => values.contains(o.value)).toList();
    final valueLabel = switch (selected.length) {
      0 => allLabel,
      1 => selected.first.label,
      _ => '${selected.first.label} +${selected.length - 1}',
    };
    return MenuAnchor(
      menuChildren: [
        for (final option in options)
          CheckboxMenuButton(
            value: values.contains(option.value),
            closeOnActivate: false,
            onChanged: (checked) {
              final next = {...values};
              if (checked ?? false) {
                next.add(option.value);
              } else {
                next.remove(option.value);
              }
              onChanged(next);
            },
            trailingIcon: option.icon == null
                ? null
                : Icon(option.icon, size: 16, color: option.color),
            child: Text(option.label),
          ),
        const Divider(height: 8),
        MenuItemButton(
          leadingIcon: const Icon(Icons.clear_all, size: 18),
          onPressed: values.isEmpty ? null : () => onChanged(<T>{}),
          child: const Text('Azzera selezione'),
        ),
      ],
      builder: (context, controller, _) => FilterButton(
        label: label,
        valueLabel: valueLabel,
        active: values.isNotEmpty,
        icon: icon,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

Widget _check(BuildContext context, bool checked) => SizedBox(
  width: 18,
  child: checked
      ? Icon(
          Icons.check,
          size: 18,
          color: Theme.of(context).colorScheme.primary,
        )
      : null,
);

/// Campo di ricerca con attesa sulla digitazione e pulsante per svuotare.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.onChanged,
    this.hint = 'Cerca…',
    this.initialValue = '',
    this.width = 280,
    this.debounce = const Duration(milliseconds: 300),
    this.focusNode,
    this.autofocus = false,
  });

  final ValueChanged<String> onChanged;
  final String hint;
  final String initialValue;
  final double width;
  final Duration debounce;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final _controller = TextEditingController(text: widget.initialValue);
  Timer? _timer;

  @override
  void didUpdateWidget(SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue &&
        widget.initialValue != _controller.text) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    setState(() {});
    _timer?.cancel();
    _timer = Timer(widget.debounce, () => widget.onChanged(value.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: 38,
      child: TextField(
        controller: _controller,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onChanged: _changed,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: const Icon(Icons.search, size: 19),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Svuota',
                  icon: const Icon(Icons.close, size: 17),
                  onPressed: () {
                    _controller.clear();
                    _timer?.cancel();
                    setState(() {});
                    widget.onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}

/// Barra dei filtri sopra tabelle ed elenchi.
class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.children,
    this.trailing = const [],
    this.onClear,
  });

  final List<Widget> children;
  final List<Widget> trailing;

  /// Se valorizzato mostra "Azzera filtri".
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ...children,
                if (onClear != null)
                  TextButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                    label: const Text('Azzera filtri'),
                  ),
              ],
            ),
          ),
          if (trailing.isNotEmpty) ...[
            const SizedBox(width: 12),
            Wrap(spacing: 8, children: trailing),
          ],
        ],
      ),
    );
  }
}

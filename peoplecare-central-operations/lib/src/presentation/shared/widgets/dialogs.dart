import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/errors.dart';
import '../../theme/app_palette.dart';

/// Struttura standard delle finestre di dialogo: titolo, contenuto
/// scorrevole e pulsanti.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.actions = const [],
    this.width = 560,
    this.padding = const EdgeInsets.fromLTRB(24, 18, 24, 20),
    this.scrollable = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;
  final List<Widget> actions;
  final double width;
  final EdgeInsetsGeometry padding;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: min(width, size.width - 48),
          maxHeight: size.height - 48,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 12, 14),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      color: Theme.of(context).colorScheme.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              subtitle!,
                              style: TextStyle(
                                color: palette.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Chiudi',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: palette.border),
            Flexible(
              child: scrollable
                  ? SingleChildScrollView(padding: padding, child: child)
                  : Padding(padding: padding, child: child),
            ),
            if (actions.isNotEmpty) ...[
              Divider(height: 1, color: palette.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      actions[i],
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Chiede conferma; `true` se l'utente conferma.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Conferma',
  bool destructive = false,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final palette = context.palette;
      return AppDialog(
        title: title,
        icon: icon ?? (destructive ? Icons.warning_amber_rounded : null),
        width: 480,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: palette.danger)
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
        child: Text(message),
      );
    },
  );
  return result ?? false;
}

/// Chiede un testo (es. il motivo di un annullamento). `null` se annullato.
Future<String?> askText(
  BuildContext context, {
  required String title,
  String? message,
  String label = 'Motivo',
  String confirmLabel = 'Conferma',
  bool required = true,
  bool destructive = false,
  List<String> suggestions = const [],
  String initialValue = '',
  int maxLines = 3,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextDialog(
      title: title,
      message: message,
      label: label,
      confirmLabel: confirmLabel,
      required: required,
      destructive: destructive,
      suggestions: suggestions,
      initialValue: initialValue,
      maxLines: maxLines,
    ),
  );
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.message,
    required this.label,
    required this.confirmLabel,
    required this.required,
    required this.destructive,
    required this.suggestions,
    required this.initialValue,
    required this.maxLines,
  });

  final String title;
  final String? message;
  final String label;
  final String confirmLabel;
  final bool required;
  final bool destructive;
  final List<String> suggestions;
  final String initialValue;
  final int maxLines;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid => !widget.required || _controller.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppDialog(
      title: widget.title,
      width: 520,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        FilledButton(
          style: widget.destructive
              ? FilledButton.styleFrom(backgroundColor: palette.danger)
              : null,
          onPressed: _valid
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          child: Text(widget.confirmLabel),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.message != null) ...[
            Text(widget.message!),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: widget.maxLines,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: widget.required ? '${widget.label} *' : widget.label,
            ),
          ),
          if (widget.suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final suggestion in widget.suggestions)
                  ActionChip(
                    label: Text(suggestion),
                    onPressed: () => setState(() {
                      _controller.text = suggestion;
                    }),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Apre un pannello laterale da destra (dettagli di servizi, operatori...).
Future<T?> showSidePanel<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double width = 720,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Chiudi pannello',
    barrierColor: Colors.black.withValues(alpha: 0.28),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) {
      final screenWidth = MediaQuery.sizeOf(context).width;
      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: min(width, screenWidth * 0.94),
          height: double.infinity,
          child: Material(
            elevation: 18,
            color: context.palette.surface,
            child: builder(context),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      );
    },
  );
}

/// Messaggio temporaneo in basso.
void showMessage(
  BuildContext context,
  String message, {
  bool error = false,
  IconData? icon,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final palette = context.palette;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: Duration(seconds: error ? 6 : 3),
        content: Row(
          children: [
            Icon(
              icon ??
                  (error ? Icons.error_outline : Icons.check_circle_outline),
              color: error ? palette.dangerSoft : const Color(0xFF9FE3B5),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

/// Esegue un'operazione mostrando l'esito; restituisce `null` in caso di
/// errore (già segnalato all'utente).
Future<T?> runGuarded<T>(
  BuildContext context,
  Future<T> Function() action, {
  String? success,
}) async {
  try {
    final result = await action();
    if (success != null && context.mounted) showMessage(context, success);
    return result;
  } on RepositoryException catch (error) {
    if (context.mounted) {
      final details =
          error is ValidationException && error.fieldErrors.isNotEmpty
          ? '\n${error.fieldErrors.values.join('\n')}'
          : '';
      showMessage(context, '${error.message}$details', error: true);
    }
    return null;
  }
}

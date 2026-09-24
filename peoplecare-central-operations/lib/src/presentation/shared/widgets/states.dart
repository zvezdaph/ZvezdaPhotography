import 'package:flutter/material.dart';

import '../../../core/errors.dart';
import '../../theme/app_palette.dart';

/// Indicatore di caricamento centrato.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(
              message!,
              style: TextStyle(color: context.palette.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Errore con pulsante per riprovare.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 40, color: palette.danger),
            const SizedBox(height: 12),
            Text(
              'Impossibile caricare i dati',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              describeError(error),
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Riprova'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Stato vuoto con icona, titolo e azione facoltativa.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    this.compact = false,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 28 : 40, color: palette.textMuted),
            SizedBox(height: compact ? 6 : 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: compact
                  ? TextStyle(
                      color: palette.textSecondary,
                      fontWeight: FontWeight.w600,
                    )
                  : Theme.of(context).textTheme.titleMedium,
            ),
            if (message != null) ...[
              const SizedBox(height: 4),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textMuted, fontSize: 13),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}

/// Barra di avanzamento sottile mostrata durante gli aggiornamenti.
class RefreshingBar extends StatelessWidget {
  const RefreshingBar({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2,
      child: visible
          ? const LinearProgressIndicator(minHeight: 2)
          : const SizedBox.shrink(),
    );
  }
}

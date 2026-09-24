import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';
import '../../theme/status_styles.dart';

/// Contenitore a scheda con intestazione opzionale.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    this.title,
    this.subtitle,
    this.icon,
    this.actions = const [],
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.headerPadding = const EdgeInsets.fromLTRB(16, 14, 12, 10),
    this.expandChild = false,
    this.color,
  });

  final String? title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry headerPadding;

  /// Il contenuto occupa lo spazio verticale rimanente (card in Expanded).
  final bool expandChild;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final body = Padding(padding: padding, child: child);
    return Container(
      decoration: BoxDecoration(
        color: color ?? palette.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        mainAxisSize: expandChild ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Padding(
              padding: headerPadding,
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 19, color: palette.textSecondary),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title!,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              subtitle!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
            Divider(height: 1, color: palette.border),
          ],
          if (expandChild) Expanded(child: body) else body,
        ],
      ),
    );
  }
}

/// Intestazione di pagina: titolo, sottotitolo e azioni.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.leading,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.headlineSmall),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      subtitle!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (actions.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
        ],
      ),
    );
  }
}

/// Titoletto di sezione dentro pannelli e form.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.padding});

  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 11.5,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
                color: context.palette.textMuted,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Coppia etichetta/valore nei dettagli.
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    this.value,
    this.child,
    this.icon,
    this.labelWidth = 150,
  }) : assert(value != null || child != null);

  final String label;
  final String? value;
  final Widget? child;
  final IconData? icon;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: palette.textMuted),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child:
                child ??
                SelectableText(
                  value!.isEmpty ? '—' : value!,
                  style: TextStyle(color: palette.textPrimary, fontSize: 14),
                ),
          ),
        ],
      ),
    );
  }
}

/// Avatar con iniziali e colore stabile.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.initials,
    required this.colorKey,
    this.size = 34,
    this.muted = false,
  });

  final String initials;
  final String colorKey;
  final double size;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = muted
        ? context.palette.textMuted
        : colorForKey(context, colorKey);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}

/// Riga orizzontale di elementi con separatore "·".
class DotSeparated extends StatelessWidget {
  const DotSeparated(this.parts, {super.key, this.style});

  final List<String> parts;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final visible = parts.where((p) => p.isNotEmpty).toList();
    return Text(
      visible.join('  ·  '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style:
          style ??
          TextStyle(color: context.palette.textSecondary, fontSize: 12.5),
    );
  }
}

/// Banner informativo/di avviso all'interno di pannelli e form.
class InlineBanner extends StatelessWidget {
  const InlineBanner({
    super.key,
    required this.style,
    required this.message,
    this.title,
    this.action,
  });

  final StatusStyle style;
  final String message;
  final String? title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: style.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(style.icon, color: style.foreground, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: style.foreground,
                    ),
                  ),
                Text(
                  message,
                  style: TextStyle(color: context.palette.textPrimary),
                ),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}

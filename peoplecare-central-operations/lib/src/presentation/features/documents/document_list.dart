import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/domain.dart';
import '../../app_scope.dart';
import '../../shared/formatters.dart';
import '../../shared/labels.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/dialogs.dart';
import '../../shared/widgets/states.dart';
import '../../theme/app_palette.dart';
import '../../theme/status_styles.dart';
import 'attachments.dart';

/// Azioni comuni sui documenti.
abstract final class DocumentActions {
  static Future<bool> markReviewed(
    BuildContext context,
    DocumentInfo document,
  ) async {
    final result = await runGuarded(
      context,
      () => context.deps.repositories.documents.markReviewed(document.id),
      success: 'Documento segnato come verificato',
    );
    return result != null;
  }

  static Future<bool> delete(
    BuildContext context,
    DocumentInfo document,
  ) async {
    if (document.source != DocumentSource.centrale) {
      showMessage(
        context,
        'I documenti ricevuti dal territorio non possono essere eliminati.',
        error: true,
      );
      return false;
    }
    final confirmed = await confirmAction(
      context,
      title: 'Eliminare il documento?',
      message: '"${document.title}" (${document.fileName}) verrà eliminato.',
      confirmLabel: 'Elimina',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return false;
    final result = await runGuarded(context, () async {
      await context.deps.repositories.documents.deleteDocument(document.id);
      return true;
    }, success: 'Documento eliminato');
    return result ?? false;
  }
}

/// Elenco compatto di documenti con azioni.
class DocumentList extends StatelessWidget {
  const DocumentList({
    super.key,
    required this.documents,
    required this.onChanged,
    this.emptyTitle = 'Nessun documento',
    this.showOwner = true,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 20),
  });

  final List<DocumentInfo> documents;
  final Future<void> Function() onChanged;
  final String emptyTitle;
  final bool showOwner;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) {
      return EmptyView(title: emptyTitle, icon: Icons.folder_off_outlined);
    }
    return ListView.separated(
      padding: padding,
      itemCount: documents.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => DocumentTile(
        document: documents[index],
        showOwner: showOwner,
        onChanged: onChanged,
      ),
    );
  }
}

class DocumentTile extends StatelessWidget {
  const DocumentTile({
    super.key,
    required this.document,
    required this.onChanged,
    this.showOwner = true,
  });

  final DocumentInfo document;
  final Future<void> Function() onChanged;
  final bool showOwner;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final pending = document.isPendingReview;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: pending
              ? palette.warning.withValues(alpha: 0.5)
              : palette.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: palette.surfaceMuted,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              fileIcon(document.extension),
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        document.title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (pending) ...[
                      const SizedBox(width: 8),
                      Pill(
                        label: 'Da verificare',
                        style: severityStyle(
                          context,
                          NotificationSeverity.attenzione,
                        ),
                        dense: true,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    document.category.label,
                    document.fileName,
                    Fmt.fileSize(document.sizeBytes),
                    if (showOwner) document.owner.label,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
                Text(
                  '${document.source.label} · ${document.uploadedBy} · '
                  '${Fmt.dateTime(document.uploadedAt)}'
                  '${document.reviewedAt == null ? '' : ' · verificato da ${document.reviewedBy}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (pending)
            TextButton.icon(
              onPressed: () async {
                if (await DocumentActions.markReviewed(context, document)) {
                  await onChanged();
                }
              },
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('Verificato'),
            ),
          IconButton(
            tooltip: 'Scarica',
            onPressed: () => unawaited(downloadDocument(context, document)),
            icon: const Icon(Icons.download_outlined),
          ),
          if (document.source == DocumentSource.centrale)
            IconButton(
              tooltip: 'Elimina',
              onPressed: () async {
                if (await DocumentActions.delete(context, document)) {
                  await onChanged();
                }
              },
              icon: Icon(Icons.delete_outline, color: palette.danger),
            ),
        ],
      ),
    );
  }
}

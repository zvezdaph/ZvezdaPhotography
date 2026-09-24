import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/domain.dart';
import '../../../platform/file_service.dart';
import '../../app_scope.dart';
import '../../shared/formatters.dart';
import '../../shared/labels.dart';
import '../../shared/widgets/dialogs.dart';
import '../../theme/app_palette.dart';
import '../../theme/status_styles.dart';

/// File scelto dall'utente, in attesa di caricamento.
class PendingAttachment {
  PendingAttachment({
    required this.file,
    required this.title,
    this.category = DocumentCategory.altro,
  });

  final PickedFile file;
  String title;
  DocumentCategory category;
}

/// Titolo proposto a partire dal nome del file.
String titleFromFileName(String name) {
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  final spaced = base.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  return spaced.isEmpty ? name : Fmt.capitalize(spaced);
}

/// Apre la finestra di scelta file e restituisce gli allegati proposti.
Future<List<PendingAttachment>> pickAttachments(
  BuildContext context, {
  DocumentCategory category = DocumentCategory.altro,
}) async {
  final files = await context.deps.files.pickFiles();
  return [
    for (final file in files)
      PendingAttachment(
        file: file,
        title: titleFromFileName(file.name),
        category: category,
      ),
  ];
}

/// Carica gli allegati sul proprietario indicato. Restituisce i documenti
/// caricati e i messaggi di errore dei file non caricati.
Future<(List<DocumentInfo>, List<String>)> uploadAttachments(
  AppDependencies deps,
  DocumentOwner owner,
  List<PendingAttachment> attachments, {
  String? description,
}) async {
  final uploaded = <DocumentInfo>[];
  final errors = <String>[];
  for (final attachment in attachments) {
    try {
      uploaded.add(
        await deps.repositories.documents.uploadDocument(
          DocumentUpload(
            owner: owner,
            title: attachment.title.trim().isEmpty
                ? attachment.file.name
                : attachment.title.trim(),
            fileName: attachment.file.name,
            mimeType: attachment.file.mimeType,
            bytes: attachment.file.bytes,
            category: attachment.category,
            description: description,
          ),
        ),
      );
    } on RepositoryException catch (error) {
      errors.add('${attachment.file.name}: ${error.message}');
    }
  }
  return (uploaded, errors);
}

/// Elenco modificabile degli allegati in attesa (titolo e categoria).
class PendingAttachmentsEditor extends StatelessWidget {
  const PendingAttachmentsEditor({
    super.key,
    required this.attachments,
    required this.onChanged,
    this.onAdd,
    this.enabled = true,
  });

  final List<PendingAttachment> attachments;
  final VoidCallback onChanged;
  final VoidCallback? onAdd;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final attachment in attachments)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.border),
              color: palette.surfaceMuted,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      fileIcon(_extension(attachment.file.name)),
                      size: 20,
                      color: palette.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        attachment.file.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      Fmt.fileSize(attachment.file.size),
                      style: TextStyle(color: palette.textMuted, fontSize: 12),
                    ),
                    IconButton(
                      tooltip: 'Rimuovi',
                      visualDensity: VisualDensity.compact,
                      onPressed: enabled
                          ? () {
                              attachments.remove(attachment);
                              onChanged();
                            }
                          : null,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        initialValue: attachment.title,
                        enabled: enabled,
                        decoration: const InputDecoration(labelText: 'Titolo'),
                        onChanged: (value) => attachment.title = value,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<DocumentCategory>(
                        initialValue: attachment.category,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Categoria',
                        ),
                        items: [
                          for (final category in DocumentCategory.values)
                            DropdownMenuItem(
                              value: category,
                              child: Text(
                                category.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: enabled
                            ? (value) {
                                if (value == null) return;
                                attachment.category = value;
                                onChanged();
                              }
                            : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (onAdd != null)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: enabled ? onAdd : null,
              icon: const Icon(Icons.attach_file, size: 18),
              label: Text(
                attachments.isEmpty ? 'Scegli file…' : 'Aggiungi altri file…',
              ),
            ),
          ),
      ],
    );
  }

  static String _extension(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }
}

/// Dialogo per caricare documenti su un proprietario noto.
Future<List<DocumentInfo>> showUploadDocumentsDialog(
  BuildContext context, {
  required DocumentOwner owner,
  DocumentCategory defaultCategory = DocumentCategory.altro,
}) async {
  final attachments = await pickAttachments(context, category: defaultCategory);
  if (attachments.isEmpty || !context.mounted) return const [];
  final result = await showDialog<List<DocumentInfo>>(
    context: context,
    builder: (_) => _UploadDialog(owner: owner, initial: attachments),
  );
  return result ?? const [];
}

class _UploadDialog extends StatefulWidget {
  const _UploadDialog({required this.owner, required this.initial});

  final DocumentOwner owner;
  final List<PendingAttachment> initial;

  @override
  State<_UploadDialog> createState() => _UploadDialogState();
}

class _UploadDialogState extends State<_UploadDialog> {
  late final List<PendingAttachment> _attachments = [...widget.initial];
  final _description = TextEditingController();
  bool _uploading = false;
  List<String> _errors = const [];

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _addMore() async {
    final more = await pickAttachments(context);
    if (!mounted) return;
    setState(() => _attachments.addAll(more));
  }

  Future<void> _upload() async {
    setState(() {
      _uploading = true;
      _errors = const [];
    });
    final deps = context.deps;
    final (uploaded, errors) = await uploadAttachments(
      deps,
      widget.owner,
      _attachments,
      description: _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
    );
    if (!mounted) return;
    if (errors.isEmpty) {
      Navigator.of(context).pop(uploaded);
      showMessage(
        context,
        uploaded.length == 1
            ? 'Documento caricato'
            : Fmt.count(
                uploaded.length,
                'documento caricato',
                'documenti caricati',
              ),
      );
      return;
    }
    setState(() {
      _uploading = false;
      _errors = errors;
      _attachments.removeWhere(
        (a) => uploaded.any((d) => d.fileName == a.file.name),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.owner.label.isEmpty
        ? widget.owner.type.label
        : widget.owner.label;
    return AppDialog(
      title: 'Carica documenti',
      subtitle: 'Associati a: $label',
      icon: Icons.upload_file_outlined,
      width: 680,
      actions: [
        TextButton(
          onPressed: _uploading ? null : () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        FilledButton.icon(
          onPressed: _uploading || _attachments.isEmpty ? null : _upload,
          icon: _uploading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_upload_outlined, size: 18),
          label: Text(
            _attachments.length <= 1
                ? 'Carica'
                : 'Carica ${_attachments.length} file',
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PendingAttachmentsEditor(
            attachments: _attachments,
            enabled: !_uploading,
            onChanged: () => setState(() {}),
            onAdd: () => unawaited(_addMore()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            enabled: !_uploading,
            decoration: const InputDecoration(
              labelText: 'Descrizione (facoltativa, per tutti i file)',
            ),
          ),
          for (final error in _errors)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error,
                style: TextStyle(color: context.palette.danger),
              ),
            ),
        ],
      ),
    );
  }
}

/// Scarica un documento e lo salva dove sceglie l'utente.
Future<void> downloadDocument(
  BuildContext context,
  DocumentInfo document,
) async {
  final deps = context.deps;
  final content = await runGuarded(
    context,
    () => deps.repositories.documents.downloadDocument(document.id),
  );
  if (content == null || !context.mounted) return;
  try {
    final path = await deps.files.saveFile(
      suggestedName: content.fileName,
      bytes: content.bytes,
      mimeType: content.mimeType,
    );
    if (path != null && context.mounted) {
      showMessage(context, 'Salvato in $path');
    }
  } catch (_) {
    if (context.mounted) {
      showMessage(context, 'Impossibile salvare il file.', error: true);
    }
  }
}

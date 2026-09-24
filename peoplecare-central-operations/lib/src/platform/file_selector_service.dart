import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'file_service.dart';

/// [FileService] basato sulle finestre di dialogo native (plugin
/// `file_selector`, supportato su Windows).
class FileSelectorService implements FileService {
  const FileSelectorService();

  static const _documents = XTypeGroup(
    label: 'Documenti e immagini',
    extensions: [
      'pdf',
      'jpg',
      'jpeg',
      'png',
      'doc',
      'docx',
      'odt',
      'xls',
      'xlsx',
      'txt',
    ],
  );

  static const _any = XTypeGroup(label: 'Tutti i file');

  @override
  Future<List<PickedFile>> pickFiles({bool multiple = true}) async {
    final files = multiple
        ? await openFiles(acceptedTypeGroups: const [_documents, _any])
        : [
            ?await openFile(acceptedTypeGroups: const [_documents, _any]),
          ];
    return [
      for (final file in files)
        PickedFile(
          name: file.name,
          bytes: await file.readAsBytes(),
          mimeType: file.mimeType ?? mimeTypeFromFileName(file.name),
        ),
    ];
  }

  @override
  Future<String?> saveFile({
    required String suggestedName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final location = await getSaveLocation(suggestedName: suggestedName);
    if (location == null) return null;
    await XFile.fromData(
      bytes,
      name: suggestedName,
      mimeType: mimeType,
    ).saveTo(location.path);
    return location.path;
  }
}

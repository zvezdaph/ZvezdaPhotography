import 'dart:typed_data';

/// File scelto dall'utente dal disco.
class PickedFile {
  const PickedFile({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });

  final String name;
  final Uint8List bytes;
  final String mimeType;

  int get size => bytes.length;
}

/// Accesso ai file locali tramite le finestre di dialogo del sistema.
///
/// La UI dipende solo da questa interfaccia; l'implementazione per Windows è
/// `FileSelectorService` (plugin `file_selector`).
abstract interface class FileService {
  /// Uno o più file da allegare; lista vuota se l'utente annulla.
  Future<List<PickedFile>> pickFiles({bool multiple = true});

  /// Salva [bytes] dove sceglie l'utente. Restituisce il percorso, o `null`
  /// se l'utente annulla.
  Future<String?> saveFile({
    required String suggestedName,
    required Uint8List bytes,
    required String mimeType,
  });
}

/// Tipo MIME dedotto dall'estensione del file.
String mimeTypeFromFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final extension = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  return switch (extension) {
    'pdf' => 'application/pdf',
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'txt' => 'text/plain',
    'csv' => 'text/csv',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'odt' => 'application/vnd.oasis.opendocument.text',
    _ => 'application/octet-stream',
  };
}

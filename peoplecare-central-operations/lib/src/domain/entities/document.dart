import 'dart:typed_data';

/// A cosa è associato un documento.
enum DocumentOwnerType {
  servizio('servizio'),
  operatore('operatore'),
  paziente('paziente'),

  /// Documenti della Centrale (procedure, turni, circolari).
  centrale('centrale');

  const DocumentOwnerType(this.code);

  final String code;

  static DocumentOwnerType fromCode(String code) => values.firstWhere(
    (type) => type.code == code,
    orElse: () =>
        throw FormatException('Proprietario del documento sconosciuto: $code'),
  );
}

/// Riferimento al proprietario di un documento.
class DocumentOwner {
  const DocumentOwner({required this.type, this.id, this.label = ''});

  const DocumentOwner.centrale()
    : type = DocumentOwnerType.centrale,
      id = null,
      label = 'Centrale Operativa';

  final DocumentOwnerType type;

  /// ID dell'entità proprietaria; `null` per i documenti della Centrale.
  final String? id;

  /// Descrizione leggibile (codice servizio, nome operatore...), fornita dal
  /// sistema in lettura.
  final String label;

  @override
  bool operator ==(Object other) =>
      other is DocumentOwner && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);
}

/// Categoria documentale.
enum DocumentCategory {
  pianoAssistenziale('piano_assistenziale'),
  consenso('consenso'),
  referto('referto'),
  verbale('verbale'),
  foglioFirma('foglio_firma'),
  certificato('certificato'),
  documentoIdentita('documento_identita'),
  procedura('procedura'),
  fotografia('fotografia'),
  altro('altro');

  const DocumentCategory(this.code);

  final String code;

  static DocumentCategory fromCode(String code) => values.firstWhere(
    (category) => category.code == code,
    orElse: () => DocumentCategory.altro,
  );
}

/// Chi ha prodotto il documento.
enum DocumentSource {
  /// Caricato dalla Centrale da questa applicazione.
  centrale('centrale'),

  /// Inviato dall'operatore dall'app mobile.
  operatore('operatore'),

  /// Generato dal sistema.
  sistema('sistema');

  const DocumentSource(this.code);

  final String code;

  static DocumentSource fromCode(String code) => values.firstWhere(
    (source) => source.code == code,
    orElse: () => DocumentSource.sistema,
  );
}

/// Metadati di un documento (il contenuto si scarica a parte).
class DocumentInfo {
  const DocumentInfo({
    required this.id,
    required this.title,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.category,
    required this.owner,
    required this.source,
    required this.uploadedBy,
    required this.uploadedAt,
    this.description,
    this.requiresReview = false,
    this.reviewedAt,
    this.reviewedBy,
  });

  final String id;
  final String title;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final DocumentCategory category;
  final DocumentOwner owner;
  final DocumentSource source;
  final String uploadedBy;
  final DateTime uploadedAt;
  final String? description;

  /// Documento ricevuto dal territorio che la Centrale deve verificare.
  final bool requiresReview;
  final DateTime? reviewedAt;
  final String? reviewedBy;

  bool get isPendingReview => requiresReview && reviewedAt == null;

  String get extension {
    final dot = fileName.lastIndexOf('.');
    return dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  }

  DocumentInfo copyWith({
    DateTime? reviewedAt,
    String? reviewedBy,
    DocumentOwner? owner,
  }) => DocumentInfo(
    id: id,
    title: title,
    fileName: fileName,
    mimeType: mimeType,
    sizeBytes: sizeBytes,
    category: category,
    owner: owner ?? this.owner,
    source: source,
    uploadedBy: uploadedBy,
    uploadedAt: uploadedAt,
    description: description,
    requiresReview: requiresReview,
    reviewedAt: reviewedAt ?? this.reviewedAt,
    reviewedBy: reviewedBy ?? this.reviewedBy,
  );
}

/// Nuovo documento da caricare.
class DocumentUpload {
  const DocumentUpload({
    required this.owner,
    required this.title,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    required this.category,
    this.description,
  });

  final DocumentOwner owner;
  final String title;
  final String fileName;
  final String mimeType;
  final Uint8List bytes;
  final DocumentCategory category;
  final String? description;
}

/// Contenuto scaricato di un documento.
class DocumentContent {
  const DocumentContent({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  final String fileName;
  final String mimeType;
  final Uint8List bytes;
}

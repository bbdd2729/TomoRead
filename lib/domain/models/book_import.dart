enum ImportSourceKind {
  filePicker,
  directoryPicker,
  desktopDrop,
  commandLine,
  androidView,
  androidShare,
}

class ImportSource {
  const ImportSource({
    required this.kind,
    required this.location,
    this.displayName,
    this.mimeType,
    this.temporary = false,
  });

  final ImportSourceKind kind;
  final String location;
  final String? displayName;
  final String? mimeType;
  final bool temporary;
}

class BookImportRequest {
  const BookImportRequest({
    required this.source,
    required this.sourcePath,
    required this.sizeBytes,
  });

  final ImportSource source;
  final String sourcePath;
  final int sizeBytes;
}

enum ImportScanDisposition { supported, skipped, duplicate, failed }

class ImportScanItem {
  const ImportScanItem({
    required this.source,
    required this.disposition,
    this.request,
    this.reason,
    this.duplicateBookId,
  });

  final ImportSource source;
  final ImportScanDisposition disposition;
  final BookImportRequest? request;
  final String? reason;
  final String? duplicateBookId;

  ImportScanItem copyWith({
    ImportScanDisposition? disposition,
    String? reason,
    String? duplicateBookId,
  }) => ImportScanItem(
    source: source,
    disposition: disposition ?? this.disposition,
    request: request,
    reason: reason ?? this.reason,
    duplicateBookId: duplicateBookId ?? this.duplicateBookId,
  );
}

class ImportScanPreview {
  const ImportScanPreview({
    required this.items,
    required this.totalBytes,
    this.cancelled = false,
    this.limitReached = false,
  });

  final List<ImportScanItem> items;
  final int totalBytes;
  final bool cancelled;
  final bool limitReached;

  int get supportedCount => _count(ImportScanDisposition.supported);
  int get skippedCount => _count(ImportScanDisposition.skipped);
  int get duplicateCount => _count(ImportScanDisposition.duplicate);
  int get failedCount => _count(ImportScanDisposition.failed);

  List<BookImportRequest> get requests => items
      .where((item) => item.disposition == ImportScanDisposition.supported)
      .map((item) => item.request)
      .whereType<BookImportRequest>()
      .toList(growable: false);

  ImportScanPreview copyWith({
    List<ImportScanItem>? items,
    int? totalBytes,
    bool? cancelled,
    bool? limitReached,
  }) => ImportScanPreview(
    items: items ?? this.items,
    totalBytes: totalBytes ?? this.totalBytes,
    cancelled: cancelled ?? this.cancelled,
    limitReached: limitReached ?? this.limitReached,
  );

  int _count(ImportScanDisposition disposition) =>
      items.where((item) => item.disposition == disposition).length;
}

class ImportScanLimits {
  const ImportScanLimits({
    this.maxEntries = 10000,
    this.maxSupportedFiles = 2000,
    this.maxFileBytes = 2 * 1024 * 1024 * 1024,
    this.maxTotalBytes = 10 * 1024 * 1024 * 1024,
  });

  final int maxEntries;
  final int maxSupportedFiles;
  final int maxFileBytes;
  final int maxTotalBytes;
}

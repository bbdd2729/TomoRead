enum ReadingFontKind { generic, systemFamily, importedFont }

enum GenericReadingFont { system, serif, sansSerif, monospace }

class ReadingFontRef {
  const ReadingFontRef._({
    required this.kind,
    required this.value,
    this.family,
  });

  ReadingFontRef.generic(GenericReadingFont font)
    : this._(kind: ReadingFontKind.generic, value: font.name);

  const ReadingFontRef.systemFamily(String family)
    : this._(
        kind: ReadingFontKind.systemFamily,
        value: family,
        family: family,
      );

  const ReadingFontRef.imported({required String id, required String family})
    : this._(
        kind: ReadingFontKind.importedFont,
        value: id,
        family: family,
      );

  static const system = ReadingFontRef._(
    kind: ReadingFontKind.generic,
    value: 'system',
  );
  static const serif = ReadingFontRef._(
    kind: ReadingFontKind.generic,
    value: 'serif',
  );
  static const sansSerif = ReadingFontRef._(
    kind: ReadingFontKind.generic,
    value: 'sansSerif',
  );
  static const monospace = ReadingFontRef._(
    kind: ReadingFontKind.generic,
    value: 'monospace',
  );

  final ReadingFontKind kind;
  final String value;
  final String? family;

  String get label => switch (kind) {
    ReadingFontKind.generic => switch (
      GenericReadingFont.values.firstWhere(
        (font) => font.name == value,
        orElse: () => GenericReadingFont.system,
      )
    ) {
      GenericReadingFont.system => '系统默认',
      GenericReadingFont.serif => '衬线字体',
      GenericReadingFont.sansSerif => '无衬线字体',
      GenericReadingFont.monospace => '等宽字体',
    },
    ReadingFontKind.systemFamily => family ?? value,
    ReadingFontKind.importedFont => '${family ?? value}（已导入）',
  };

  String? get fontFamily => switch (kind) {
    ReadingFontKind.generic => switch (value) {
      'serif' => 'serif',
      'sansSerif' => 'sans-serif',
      'monospace' => 'monospace',
      _ => null,
    },
    ReadingFontKind.systemFamily => family ?? value,
    ReadingFontKind.importedFont => runtimeFamily,
  };

  String? get importedFontId =>
      kind == ReadingFontKind.importedFont ? value : null;

  String get runtimeFamily => kind == ReadingFontKind.importedFont
      ? 'TomoReadImported-$value'
      : (family ?? value);

  String get storageValue {
    final escapedFamily = Uri.encodeComponent(family ?? '');
    return '${kind.name}:$value:$escapedFamily';
  }

  static ReadingFontRef parse(Object? source) {
    final text = source?.toString() ?? '';
    switch (text) {
      case 'system':
      case 'generic:system:':
        return system;
      case 'serif':
      case 'generic:serif:':
        return serif;
      case 'sansSerif':
      case 'generic:sansSerif:':
        return sansSerif;
      case 'monospace':
      case 'generic:monospace:':
        return monospace;
    }
    final parts = text.split(':');
    if (parts.length < 2) return system;
    final kind = ReadingFontKind.values.where((item) => item.name == parts[0]);
    if (kind.isEmpty) return system;
    final value = parts[1];
    final family = parts.length > 2 && parts[2].isNotEmpty
        ? Uri.decodeComponent(parts.sublist(2).join(':'))
        : null;
    return switch (kind.first) {
      ReadingFontKind.generic => ReadingFontRef.generic(
        GenericReadingFont.values.firstWhere(
          (font) => font.name == value,
          orElse: () => GenericReadingFont.system,
        ),
      ),
      ReadingFontKind.systemFamily => ReadingFontRef.systemFamily(
        family ?? value,
      ),
      ReadingFontKind.importedFont => ReadingFontRef.imported(
        id: value,
        family: family ?? value,
      ),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ReadingFontRef &&
      other.kind == kind &&
      other.value == value &&
      other.family == family;

  @override
  int get hashCode => Object.hash(kind, value, family);
}

class SystemFontFamily {
  const SystemFontFamily({required this.family, this.styles = const []});

  final String family;
  final List<String> styles;
}

class ImportedFont {
  const ImportedFont({
    required this.id,
    required this.family,
    required this.fileName,
    required this.filePath,
    required this.fileHash,
    required this.format,
    required this.source,
    required this.createdAt,
    this.licenseLabel,
  });

  final String id;
  final String family;
  final String fileName;
  final String filePath;
  final String fileHash;
  final String format;
  final String source;
  final String? licenseLabel;
  final DateTime createdAt;

  ReadingFontRef get ref => ReadingFontRef.imported(id: id, family: family);
}

class ImportedFontReferenceException implements Exception {
  const ImportedFontReferenceException(this.fontId, this.bookIds);

  final String fontId;
  final List<String> bookIds;

  @override
  String toString() => '该字体仍被全局设置或 ${bookIds.length} 本书引用。';
}

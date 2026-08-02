enum ChineseConversionMode {
  off,
  traditionalToSimplified,
  simplifiedToTraditional,
  simplifiedToTaiwan,
  simplifiedToHongKong,
}

enum CharacterWidthMode { unchanged, toHalfWidth, toFullWidth }

class TextProjectionSettings {
  const TextProjectionSettings({
    this.chineseConversion = ChineseConversionMode.off,
    this.widthMode = CharacterWidthMode.unchanged,
    this.convertLetters = true,
    this.convertNumbers = true,
  });

  final ChineseConversionMode chineseConversion;
  final CharacterWidthMode widthMode;
  final bool convertLetters;
  final bool convertNumbers;

  bool get enabled =>
      chineseConversion != ChineseConversionMode.off ||
      widthMode != CharacterWidthMode.unchanged;

  TextProjectionSettings copyWith({
    ChineseConversionMode? chineseConversion,
    CharacterWidthMode? widthMode,
    bool? convertLetters,
    bool? convertNumbers,
  }) => TextProjectionSettings(
    chineseConversion: chineseConversion ?? this.chineseConversion,
    widthMode: widthMode ?? this.widthMode,
    convertLetters: convertLetters ?? this.convertLetters,
    convertNumbers: convertNumbers ?? this.convertNumbers,
  );

  Map<String, Object> toJson() => {
    'chineseConversion': chineseConversion.name,
    'widthMode': widthMode.name,
    'convertLetters': convertLetters,
    'convertNumbers': convertNumbers,
  };

  factory TextProjectionSettings.fromJson(Map<String, Object?> value) =>
      TextProjectionSettings(
        chineseConversion: ChineseConversionMode.values.firstWhere(
          (item) => item.name == value['chineseConversion'],
          orElse: () => ChineseConversionMode.off,
        ),
        widthMode: CharacterWidthMode.values.firstWhere(
          (item) => item.name == value['widthMode'],
          orElse: () => CharacterWidthMode.unchanged,
        ),
        convertLetters: value['convertLetters'] as bool? ?? true,
        convertNumbers: value['convertNumbers'] as bool? ?? true,
      );
}

class TextDisplayRule {
  const TextDisplayRule({
    required this.id,
    required this.name,
    required this.findText,
    required this.replaceText,
    required this.enabled,
    required this.priority,
    required this.createdAt,
    required this.updatedAt,
    this.bookId,
  });

  final String id;
  final String? bookId;
  final String name;
  final String findText;
  final String replaceText;
  final bool enabled;
  final int priority;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool appliesTo(String targetBookId) =>
      enabled && (bookId == null || bookId == targetBookId);
}

class ProjectionRange {
  const ProjectionRange({
    required this.start,
    required this.end,
    required this.isExact,
  });

  final int start;
  final int end;
  final bool isExact;
}

class ProjectionSegment {
  const ProjectionSegment({
    required this.rawStart,
    required this.rawEnd,
    required this.displayStart,
    required this.displayEnd,
    required this.isExact,
  });

  final int rawStart;
  final int rawEnd;
  final int displayStart;
  final int displayEnd;
  final bool isExact;
}

class DisplayProjection {
  const DisplayProjection({
    required this.rawText,
    required this.displayText,
    required this.segments,
    required this.mappingCells,
  });

  factory DisplayProjection.identity(String text) => DisplayProjection(
    rawText: text,
    displayText: text,
    segments: [
      ProjectionSegment(
        rawStart: 0,
        rawEnd: text.length,
        displayStart: 0,
        displayEnd: text.length,
        isExact: true,
      ),
    ],
    mappingCells: [
      for (var index = 0; index < text.length; index++)
        ProjectionCell(rawStart: index, rawEnd: index + 1, isExact: true),
    ],
  );

  final String rawText;
  final String displayText;
  final List<ProjectionSegment> segments;
  final List<ProjectionCell> mappingCells;

  bool get hasAmbiguousRanges => segments.any((segment) => !segment.isExact);

  ProjectionRange displayToRaw(int start, int end) {
    final safeStart = start.clamp(0, displayText.length).toInt();
    final safeEnd = end.clamp(safeStart, displayText.length).toInt();
    if (safeStart == safeEnd) {
      final offset = safeStart == mappingCells.length
          ? rawText.length
          : mappingCells[safeStart].rawStart;
      return ProjectionRange(start: offset, end: offset, isExact: true);
    }
    final cells = mappingCells.sublist(safeStart, safeEnd);
    var contiguous = true;
    for (var index = 1; index < cells.length; index++) {
      if (cells[index - 1].rawEnd != cells[index].rawStart) {
        contiguous = false;
        break;
      }
    }
    return ProjectionRange(
      start: cells.first.rawStart,
      end: cells.last.rawEnd,
      isExact: contiguous && cells.every((cell) => cell.isExact),
    );
  }

  ProjectionRange rawToDisplay(int start, int end) {
    final safeStart = start.clamp(0, rawText.length).toInt();
    final safeEnd = end.clamp(safeStart, rawText.length).toInt();
    final indices = <int>[];
    for (var index = 0; index < mappingCells.length; index++) {
      final cell = mappingCells[index];
      if (cell.rawEnd > safeStart && cell.rawStart < safeEnd) indices.add(index);
    }
    if (indices.isEmpty) {
      return ProjectionRange(start: 0, end: 0, isExact: safeStart == safeEnd);
    }
    final cells = indices.map((index) => mappingCells[index]);
    return ProjectionRange(
      start: indices.first,
      end: indices.last + 1,
      isExact: cells.every((cell) => cell.isExact),
    );
  }
}

class ProjectionCell {
  const ProjectionCell({
    required this.rawStart,
    required this.rawEnd,
    required this.isExact,
  });

  final int rawStart;
  final int rawEnd;
  final bool isExact;
}

extension ChineseConversionModeLabel on ChineseConversionMode {
  String get label => switch (this) {
    ChineseConversionMode.off => '关闭',
    ChineseConversionMode.traditionalToSimplified => '繁体转简体',
    ChineseConversionMode.simplifiedToTraditional => '简体转标准繁体',
    ChineseConversionMode.simplifiedToTaiwan => '简体转台湾繁体',
    ChineseConversionMode.simplifiedToHongKong => '简体转香港繁体',
  };
}

extension CharacterWidthModeLabel on CharacterWidthMode {
  String get label => switch (this) {
    CharacterWidthMode.unchanged => '不转换',
    CharacterWidthMode.toHalfWidth => '转半角',
    CharacterWidthMode.toFullWidth => '转全角',
  };
}

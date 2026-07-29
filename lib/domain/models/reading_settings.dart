import 'font_choice.dart';

enum ReaderLayoutMode { scroll, paginated }

extension ReaderLayoutModeLabel on ReaderLayoutMode {
  String get label => switch (this) {
    ReaderLayoutMode.scroll => '滚动',
    ReaderLayoutMode.paginated => '分页',
  };
}

class ReadingSettings {
  const ReadingSettings({
    this.font = FontChoice.system,
    this.fontSize = 19,
    this.lineHeight = 1.9,
    this.pageMargin = 32,
    this.doubleColumn = true,
    this.layoutMode = ReaderLayoutMode.scroll,
  });

  final FontChoice font;
  final double fontSize;
  final double lineHeight;
  final double pageMargin;
  final bool doubleColumn;
  final ReaderLayoutMode layoutMode;

  ReadingSettings copyWith({
    FontChoice? font,
    double? fontSize,
    double? lineHeight,
    double? pageMargin,
    bool? doubleColumn,
    ReaderLayoutMode? layoutMode,
  }) {
    return ReadingSettings(
      font: font ?? this.font,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      pageMargin: pageMargin ?? this.pageMargin,
      doubleColumn: doubleColumn ?? this.doubleColumn,
      layoutMode: layoutMode ?? this.layoutMode,
    );
  }
}

class BookReadingOverride {
  const BookReadingOverride({required this.bookId, required this.settings});

  final String bookId;
  final ReadingSettings settings;
}

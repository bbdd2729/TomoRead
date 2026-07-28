import 'font_choice.dart';

class ReadingSettings {
  const ReadingSettings({
    this.font = FontChoice.system,
    this.fontSize = 19,
    this.lineHeight = 1.9,
    this.pageMargin = 32,
    this.doubleColumn = true,
  });

  final FontChoice font;
  final double fontSize;
  final double lineHeight;
  final double pageMargin;
  final bool doubleColumn;

  ReadingSettings copyWith({
    FontChoice? font,
    double? fontSize,
    double? lineHeight,
    double? pageMargin,
    bool? doubleColumn,
  }) {
    return ReadingSettings(
      font: font ?? this.font,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      pageMargin: pageMargin ?? this.pageMargin,
      doubleColumn: doubleColumn ?? this.doubleColumn,
    );
  }
}

class BookReadingOverride {
  const BookReadingOverride({required this.bookId, required this.settings});

  final String bookId;
  final ReadingSettings settings;
}

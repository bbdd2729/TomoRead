import 'reading_font.dart';
import 'reader_theme.dart';

enum ReaderLayoutMode { scroll, paginated }

extension ReaderLayoutModeLabel on ReaderLayoutMode {
  String get label => switch (this) {
    ReaderLayoutMode.scroll => '滚动',
    ReaderLayoutMode.paginated => '分页',
  };
}

enum ReaderPageTransition { slide, cover, fade, none }

extension ReaderPageTransitionLabel on ReaderPageTransition {
  String get label => switch (this) {
    ReaderPageTransition.slide => '滑动',
    ReaderPageTransition.cover => '覆盖',
    ReaderPageTransition.fade => '淡入',
    ReaderPageTransition.none => '无动画',
  };
}

class ReadingSettings {
  const ReadingSettings({
    this.font = ReadingFontRef.system,
    this.fontSize = 19,
    this.lineHeight = 1.9,
    this.pageMargin = 32,
    this.doubleColumn = true,
    this.layoutMode = ReaderLayoutMode.scroll,
    this.pageTransition = ReaderPageTransition.slide,
    this.tapToTurnPages = false,
    this.theme = const ReaderThemeSelection(),
  });

  final ReadingFontRef font;
  final double fontSize;
  final double lineHeight;
  final double pageMargin;
  final bool doubleColumn;
  final ReaderLayoutMode layoutMode;
  final ReaderPageTransition pageTransition;
  final bool tapToTurnPages;
  final ReaderThemeSelection theme;

  ReadingSettings copyWith({
    ReadingFontRef? font,
    double? fontSize,
    double? lineHeight,
    double? pageMargin,
    bool? doubleColumn,
    ReaderLayoutMode? layoutMode,
    ReaderPageTransition? pageTransition,
    bool? tapToTurnPages,
    ReaderThemeSelection? theme,
  }) {
    return ReadingSettings(
      font: font ?? this.font,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      pageMargin: pageMargin ?? this.pageMargin,
      doubleColumn: doubleColumn ?? this.doubleColumn,
      layoutMode: layoutMode ?? this.layoutMode,
      pageTransition: pageTransition ?? this.pageTransition,
      tapToTurnPages: tapToTurnPages ?? this.tapToTurnPages,
      theme: theme ?? this.theme,
    );
  }
}

class BookReadingOverride {
  const BookReadingOverride({required this.bookId, required this.settings});

  final String bookId;
  final ReadingSettings settings;
}

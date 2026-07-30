import 'font_choice.dart';

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
    this.font = FontChoice.system,
    this.fontSize = 19,
    this.lineHeight = 1.9,
    this.pageMargin = 32,
    this.doubleColumn = true,
    this.layoutMode = ReaderLayoutMode.scroll,
    this.pageTransition = ReaderPageTransition.slide,
  });

  final FontChoice font;
  final double fontSize;
  final double lineHeight;
  final double pageMargin;
  final bool doubleColumn;
  final ReaderLayoutMode layoutMode;
  final ReaderPageTransition pageTransition;

  ReadingSettings copyWith({
    FontChoice? font,
    double? fontSize,
    double? lineHeight,
    double? pageMargin,
    bool? doubleColumn,
    ReaderLayoutMode? layoutMode,
    ReaderPageTransition? pageTransition,
  }) {
    return ReadingSettings(
      font: font ?? this.font,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      pageMargin: pageMargin ?? this.pageMargin,
      doubleColumn: doubleColumn ?? this.doubleColumn,
      layoutMode: layoutMode ?? this.layoutMode,
      pageTransition: pageTransition ?? this.pageTransition,
    );
  }
}

class BookReadingOverride {
  const BookReadingOverride({required this.bookId, required this.settings});

  final String bookId;
  final ReadingSettings settings;
}

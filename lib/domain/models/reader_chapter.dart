class ReaderChapter {
  const ReaderChapter({
    required this.index,
    required this.href,
    required this.title,
    required this.blocks,
  });

  final int index;
  final String href;
  final String title;
  final List<ReaderChapterBlock> blocks;

  String get plainText => blocks.map((block) => block.text).join('\n');
}

class EpubSearchResult {
  const EpubSearchResult({
    required this.chapterIndex,
    required this.href,
    required this.chapterTitle,
    required this.excerpt,
    required this.chapterRatio,
  });

  final int chapterIndex;
  final String href;
  final String chapterTitle;
  final String excerpt;
  final double chapterRatio;
}

class ReaderChapterBlock {
  const ReaderChapterBlock({required this.text, required this.isHeading});

  final String text;
  final bool isHeading;
}

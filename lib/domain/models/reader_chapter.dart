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
}

class ReaderChapterBlock {
  const ReaderChapterBlock({required this.text, required this.isHeading});

  final String text;
  final bool isHeading;
}

enum ReadingContextKind { selection, currentChapter, annotation, indexHit }

enum ReadingAssistantAction {
  explainSelection,
  summarizeChapter,
  generateQuestions,
  extractPeopleAndTerms,
  buildTimeline,
}

class ReadingContextSelection {
  const ReadingContextSelection({
    required this.text,
    required this.href,
    required this.locator,
    required this.chapterIndex,
    required this.chapterTitle,
  });

  final String text;
  final String href;
  final String locator;
  final int chapterIndex;
  final String chapterTitle;
}

class ReadingContextSegment {
  const ReadingContextSegment({
    required this.kind,
    required this.bookId,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.href,
    required this.locator,
    required this.text,
    required this.contentHash,
  });

  final ReadingContextKind kind;
  final String bookId;
  final int chapterIndex;
  final String chapterTitle;
  final String href;
  final String locator;
  final String text;
  final String contentHash;

  int get characterCount => text.length;
}

class ReadingContextBundle {
  const ReadingContextBundle({
    required this.bookId,
    required this.currentChapterIndex,
    required this.segments,
    required this.characterBudget,
    required this.usedCharacters,
    required this.contextHash,
    required this.spoilerLimited,
  });

  final String bookId;
  final int currentChapterIndex;
  final List<ReadingContextSegment> segments;
  final int characterBudget;
  final int usedCharacters;
  final String contextHash;
  final bool spoilerLimited;
}

extension ReadingAssistantActionInfo on ReadingAssistantAction {
  String get label => switch (this) {
    ReadingAssistantAction.explainSelection => '解释选区',
    ReadingAssistantAction.summarizeChapter => '总结当前章节',
    ReadingAssistantAction.generateQuestions => '生成阅读问题',
    ReadingAssistantAction.extractPeopleAndTerms => '提取人物与术语',
    ReadingAssistantAction.buildTimeline => '梳理时间线',
  };

  String get prompt => switch (this) {
    ReadingAssistantAction.explainSelection =>
      '请解释所选原文的含义、关键词和它在当前章节中的作用。',
    ReadingAssistantAction.summarizeChapter =>
      '请总结当前章节的核心事件、论点和结论，并为书内事实附上引用。',
    ReadingAssistantAction.generateQuestions =>
      '请根据当前章节生成一组帮助复习和深入思考的阅读问题。',
    ReadingAssistantAction.extractPeopleAndTerms =>
      '请提取当前章节的重要人物、组织、地点和术语，给出简洁说明。',
    ReadingAssistantAction.buildTimeline =>
      '请按原文顺序梳理当前章节的事件时间线，并为关键节点附上引用。',
  };
}

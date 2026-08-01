import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:tomoread/app/providers.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/book_repository.dart';
import 'package:tomoread/domain/models/annotation_query.dart';
import 'package:tomoread/domain/models/chat_models.dart';
import 'package:tomoread/domain/models/epub_location.dart';
import 'package:tomoread/domain/models/epub_manifest.dart';
import 'package:tomoread/domain/models/library_book.dart';
import 'package:tomoread/domain/models/reading_annotation.dart';
import 'package:tomoread/domain/models/stats_models.dart';
import 'package:tomoread/features/chat/chat_controller.dart';
import 'package:tomoread/features/chat/chat_page.dart';
import 'package:tomoread/features/notes/notes_page.dart';
import 'package:tomoread/features/notes/notes_providers.dart';
import 'package:tomoread/features/statistics/statistics_page.dart';
import 'package:tomoread/features/statistics/statistics_providers.dart';

void main() {
  testWidgets('chat page exposes model setup and a usable composer', (
    tester,
  ) async {
    await _pumpPage(tester, const ChatPage(), [
      chatControllerProvider.overrideWith(_EmptyChatController.new),
      libraryBooksProvider.overrideWith(_EmptyLibraryBooksNotifier.new),
    ]);

    expect(find.text('尚未配置模型'), findsOneWidget);
    expect(find.byKey(const Key('chat-composer')), findsOneWidget);
    expect(find.text('配置模型'), findsOneWidget);
  });

  testWidgets('chat renders reasoning, tool, skill, and citation parts', (
    tester,
  ) async {
    await _pumpPage(tester, const ChatPage(), [
      chatControllerProvider.overrideWith(_PartsChatController.new),
      libraryBooksProvider.overrideWith(_EmptyLibraryBooksNotifier.new),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('思考摘要'), findsOneWidget);
    expect(find.text('读取目录'), findsOneWidget);
    expect(find.text('章节总结'), findsOneWidget);
    expect(find.text('第一章'), findsOneWidget);
    expect(find.text('回答正文 [1]'), findsOneWidget);
  });

  testWidgets('notes page renders a real empty state on compact layouts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(680, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpPage(tester, const NotesPage(), [
      annotationItemsProvider.overrideWith(
        (ref) async => const <AnnotationListItem>[],
      ),
      annotationFacetsProvider.overrideWith(
        (ref) async =>
            const AnnotationFacets(totalCount: 0, noteCount: 0, tags: []),
      ),
      libraryBooksProvider.overrideWith(_EmptyLibraryBooksNotifier.new),
    ]);

    expect(find.byKey(const Key('notes-search')), findsOneWidget);
    expect(find.text('还没有符合条件的笔记'), findsOneWidget);
  });

  testWidgets('opens an annotation at the chapter resolved from its href', (
    tester,
  ) async {
    const manifest = EpubManifest(
      opfPath: 'OEBPS/content.opf',
      version: '3.0',
      direction: ReadingDirection.ltr,
      spine: [
        EpubSpineItem(
          id: 'cover',
          href: 'OEBPS/Text/cover.xhtml',
          linear: true,
        ),
        EpubSpineItem(
          id: 'chapter-1',
          href: 'OEBPS/Text/chapter-1.xhtml',
          linear: true,
        ),
      ],
      toc: [],
    );
    final book = LibraryBook(
      id: 'book-a',
      fileHash: 'hash-a',
      title: 'Book A',
      author: 'Author',
      filePath: 'book.epub',
      progress: 0,
      importedAt: DateTime(2026),
      format: 'epub',
      chapterCount: 2,
      direction: ReadingDirection.ltr,
    );
    final repository = _CapturingBookRepository(manifest);
    final item = AnnotationListItem(
      annotation: ReadingAnnotation(
        id: 'annotation-a',
        bookId: book.id,
        href: 'OEBPS/Text/chapter-1.xhtml',
        locator: 'cfi:epubcfi(/6/4!/4/2/2)',
        selectedText: 'Selected text',
        color: AnnotationColor.yellow,
        createdAt: DateTime(2026),
        chapterIndex: 0,
        chapterTitle: 'Chapter 1',
      ),
      book: book,
    );
    LibraryBook? openedBook;

    await _pumpPage(
      tester,
      NotesPage(onOpenReader: (book) => openedBook = book),
      [
        bookRepositoryProvider.overrideWithValue(repository),
        annotationItemsProvider.overrideWith((ref) async => [item]),
        annotationFacetsProvider.overrideWith(
          (ref) async =>
              const AnnotationFacets(totalCount: 1, noteCount: 0, tags: []),
        ),
        libraryBooksProvider.overrideWith(_EmptyLibraryBooksNotifier.new),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Selected text').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.open_in_new));
    for (var attempt = 0; attempt < 20 && openedBook == null; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final location = EpubLocation.fromLocator(
      repository.locator,
      fallbackChapterIndex: 0,
    );
    expect(openedBook?.id, book.id);
    expect(repository.chapterIndex, 1);
    expect(location.chapterIndex, 1);
    expect(location.cfi, 'epubcfi(/6/4!/4/2/2)');
  });

  testWidgets('statistics page reports that the selected period is empty', (
    tester,
  ) async {
    await _pumpPage(tester, const StatisticsPage(), [
      statsReportProvider.overrideWith((ref) async => _emptyStatsReport),
    ]);

    expect(find.text('阅读统计'), findsOneWidget);
    expect(find.textContaining('还没有阅读记录'), findsOneWidget);
    expect(find.text('日'), findsOneWidget);
    expect(find.text('周'), findsOneWidget);
  });
}

class _EmptyChatController extends ChatController {
  @override
  Future<ChatPageState> build() async =>
      const ChatPageState(threads: [], messages: []);
}

class _PartsChatController extends ChatController {
  @override
  Future<ChatPageState> build() async {
    final now = DateTime(2026);
    const threadId = 'thread-parts';
    const messageId = 'message-parts';
    final citation = ChatCitation(
      id: 'citation-parts',
      messageId: messageId,
      ordinal: 1,
      bookId: 'book-a',
      href: 'chapter.xhtml',
      locator: 'ratio:0.2',
      chapterIndex: 0,
      chapterTitle: '第一章',
      quote: '引用原文',
    );
    return ChatPageState(
      activeThreadId: threadId,
      threads: [
        ChatThread(
          id: threadId,
          scope: ChatScope.book,
          bookId: 'book-a',
          title: '结构化消息',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      messages: [
        ChatMessage(
          id: messageId,
          threadId: threadId,
          role: ChatRole.assistant,
          content: '回答正文 [1]',
          status: ChatMessageStatus.complete,
          modelId: 'model-a',
          createdAt: now,
          completedAt: now,
          citations: [citation],
          parts: [
            ChatReasoningPart(
              id: 'reasoning-a',
              messageId: messageId,
              ordinal: 0,
              status: ChatPartStatus.completed,
              createdAt: now,
              updatedAt: now,
              text: '思考摘要内容',
            ),
            ChatToolCallPart(
              id: 'tool-a',
              messageId: messageId,
              ordinal: 1,
              status: ChatPartStatus.completed,
              createdAt: now,
              updatedAt: now,
              callId: 'call-a',
              toolName: 'get_table_of_contents',
              displayName: '读取目录',
              result: '完成',
            ),
            ChatSkillCallPart(
              id: 'skill-a',
              messageId: messageId,
              ordinal: 2,
              status: ChatPartStatus.completed,
              createdAt: now,
              updatedAt: now,
              callId: 'call-b',
              skillId: 'chapter-summary',
              skillName: '章节总结',
              result: '完成',
            ),
            ChatTextPart(
              id: 'text-a',
              messageId: messageId,
              ordinal: 3,
              status: ChatPartStatus.completed,
              createdAt: now,
              updatedAt: now,
              text: '回答正文 [1]',
            ),
            ChatCitationPart(
              id: 'citation-part-a',
              messageId: messageId,
              ordinal: 4,
              status: ChatPartStatus.completed,
              createdAt: now,
              updatedAt: now,
              citation: citation,
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptyLibraryBooksNotifier extends LibraryBooksNotifier {
  @override
  Future<List<LibraryBook>> build() async => const [];
}

class _CapturingBookRepository extends BookRepository {
  _CapturingBookRepository(this.manifest) : super(AppDatabase.inMemory());

  final EpubManifest manifest;
  int? chapterIndex;
  String? locator;

  @override
  Future<EpubManifest?> loadManifest(String bookId) async => manifest;

  @override
  Future<void> updateReadingPosition({
    required String bookId,
    required int chapterIndex,
    required double progress,
    String? locator,
  }) async {
    this.chapterIndex = chapterIndex;
    this.locator = locator;
  }
}

const _emptyStatsReport = StatsReport(
  dimension: StatsDimension.week,
  period: StatsPeriod(
    startKey: '2026-07-27',
    endKey: '2026-08-02',
    label: '7月27日 - 8月2日',
  ),
  summary: StatsSummary(
    activeMillis: 0,
    activeDays: 0,
    sessionCount: 0,
    booksTouched: 0,
    currentStreak: 0,
  ),
  timeline: [],
  topBooks: [],
  canGoNext: false,
);

Future<void> _pumpPage(
  WidgetTester tester,
  Widget page,
  List<Override> overrides,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: page)),
    ),
  );
  await tester.pump();
}

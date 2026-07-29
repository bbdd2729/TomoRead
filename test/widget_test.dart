import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/app/appearance.dart';
import 'package:tomoread/app/providers.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/annotation_repository.dart';
import 'package:tomoread/data/repositories/bookmark_repository.dart';
import 'package:tomoread/data/repositories/book_repository.dart';
import 'package:tomoread/data/repositories/settings_repository.dart';
import 'package:tomoread/domain/models/bookmark.dart';
import 'package:tomoread/domain/models/epub_manifest.dart';
import 'package:tomoread/domain/models/library_book.dart';
import 'package:tomoread/domain/models/reading_settings.dart';
import 'package:tomoread/domain/models/reading_annotation.dart';
import 'package:tomoread/features/reader/reader_workspace.dart';
import 'package:tomoread/features/workspace/app_shell.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  void configureDesktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpShell(
    WidgetTester tester, {
    ValueChanged<AppAppearance>? onAppearanceChanged,
    List<LibraryBook> books = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            _FakeSettingsRepository(),
          ),
          bookmarkRepositoryProvider.overrideWithValue(
            _FakeBookmarkRepository(),
          ),
          annotationRepositoryProvider.overrideWithValue(
            _FakeAnnotationRepository(),
          ),
          bookRepositoryProvider.overrideWithValue(_FakeBookRepository(books)),
        ],
        child: MaterialApp(
          home: AppShell(
            appearance: const AppAppearance(),
            readingSettings: const ReadingSettings(),
            onImportBooks: () async {},
            onAppearanceChanged: onAppearanceChanged ?? (_) {},
            onReadingSettingsChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders the desktop library workspace', (tester) async {
    configureDesktop(tester);
    await pumpShell(tester);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byKey(const Key('settings-navigation')), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('collapses desktop navigation and stores the preference', (
    tester,
  ) async {
    configureDesktop(tester);
    AppAppearance? changedAppearance;
    await pumpShell(
      tester,
      onAppearanceChanged: (appearance) => changedAppearance = appearance,
    );

    await tester.tap(find.byKey(const Key('desktop-navigation-toggle')));
    await tester.pump();

    expect(changedAppearance?.desktopNavigationCollapsed, isTrue);
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
      isFalse,
    );
  });

  testWidgets('adds a bookmark and collapses the reader toc', (tester) async {
    configureDesktop(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            _FakeSettingsRepository(),
          ),
          bookmarkRepositoryProvider.overrideWithValue(
            _FakeBookmarkRepository(),
          ),
          annotationRepositoryProvider.overrideWithValue(
            _FakeAnnotationRepository(),
          ),
          bookRepositoryProvider.overrideWithValue(_FakeBookRepository()),
        ],
        child: MaterialApp(
          home: ReaderWorkspace(
            bookId: 'book-a',
            title: 'Test book',
            readingSettings: const ReadingSettings(),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader-bookmark')));
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.bookmark), findsWidgets);

    await tester.tap(find.byKey(const Key('reader-toc')));
    await tester.pump();
    expect(find.byIcon(Icons.menu_open), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-focus-mode')));
    await tester.pump();
    expect(find.byKey(const Key('reader-footer')), findsNothing);
  });

  testWidgets('opens settings from the single navigation entry', (
    tester,
  ) async {
    configureDesktop(tester);
    AppAppearance? changedAppearance;
    await pumpShell(
      tester,
      onAppearanceChanged: (appearance) => changedAppearance = appearance,
    );

    await tester.tap(find.byKey(const Key('settings-navigation')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('theme-green')));
    await tester.pump();

    expect(changedAppearance?.seed, ThemeSeed.green);
  });

  testWidgets('shows the full per-book reading settings', (tester) async {
    configureDesktop(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            _FakeSettingsRepository(),
          ),
          bookmarkRepositoryProvider.overrideWithValue(
            _FakeBookmarkRepository(),
          ),
          annotationRepositoryProvider.overrideWithValue(
            _FakeAnnotationRepository(),
          ),
          bookRepositoryProvider.overrideWithValue(_FakeBookRepository()),
        ],
        child: const MaterialApp(
          home: ReaderWorkspace(
            bookId: 'book-a',
            title: 'Test book',
            readingSettings: ReadingSettings(),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader-book-settings')));
    await tester.pump();
    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(find.byKey(const Key('book-reading-margin')), findsOneWidget);
    expect(find.byKey(const Key('book-reading-double-column')), findsOneWidget);
  });

  testWidgets('filters the library by title or author', (tester) async {
    configureDesktop(tester);
    final epub = LibraryBook(
      id: 'epub-book',
      fileHash: 'epub-book',
      title: 'Dart Patterns',
      author: 'Alice',
      filePath: 'C:/books/dart.epub',
      progress: 0.4,
      importedAt: DateTime(2026),
      format: 'epub',
      chapterCount: 8,
      direction: ReadingDirection.ltr,
    );
    final pdf = LibraryBook(
      id: 'pdf-book',
      fileHash: 'pdf-book',
      title: 'PDF Notes',
      author: 'Bob',
      filePath: 'C:/books/notes.pdf',
      progress: 0,
      importedAt: DateTime(2025),
      format: 'pdf',
      chapterCount: 12,
      direction: ReadingDirection.ltr,
    );
    await pumpShell(tester, books: [epub, pdf]);

    expect(find.byKey(const Key('book-epub-book')), findsOneWidget);
    expect(find.byKey(const Key('book-pdf-book')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('library-search')), 'alice');
    await tester.pump();

    expect(find.byKey(const Key('book-epub-book')), findsOneWidget);
    expect(find.byKey(const Key('book-pdf-book')), findsNothing);

    await tester.enterText(find.byKey(const Key('library-search')), '');
    await tester.pump();
    await tester.tap(find.text('PDF'));
    await tester.pump();

    expect(find.byKey(const Key('book-epub-book')), findsNothing);
    expect(find.byKey(const Key('book-pdf-book')), findsOneWidget);
  });

  testWidgets('switches the library to list view', (tester) async {
    configureDesktop(tester);
    final book = LibraryBook(
      id: 'list-view-book',
      fileHash: 'list-view-book',
      title: 'List view title',
      author: 'Author',
      filePath: 'C:/books/list.epub',
      progress: 0.5,
      importedAt: DateTime(2026),
      format: 'epub',
      chapterCount: 4,
      direction: ReadingDirection.ltr,
    );
    await pumpShell(tester, books: [book]);

    await tester.tap(find.byIcon(Icons.view_list_outlined));
    await tester.pump();

    expect(find.byKey(const Key('book-list-list-view-book')), findsOneWidget);
  });

  testWidgets('searches the library from the app bar', (tester) async {
    configureDesktop(tester);
    final book = LibraryBook(
      id: 'global-search-book',
      fileHash: 'global-search-book',
      title: 'Searchable Book',
      author: 'Alice',
      filePath: 'C:/books/search.epub',
      progress: 0.2,
      importedAt: DateTime(2026),
      format: 'epub',
      chapterCount: 1,
      direction: ReadingDirection.ltr,
    );
    await pumpShell(tester, books: [book]);

    await tester.tap(find.byKey(const Key('global-search')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    tester.testTextInput.enterText('searchable');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'Searchable Book'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(ReaderWorkspace), findsOneWidget);
  });

  testWidgets('removes a book after confirmation', (tester) async {
    configureDesktop(tester);
    final book = LibraryBook(
      id: 'book-delete',
      fileHash: 'book-delete',
      title: 'Delete me',
      author: '',
      filePath: 'C:/books/delete.epub',
      progress: 0,
      importedAt: DateTime(2026),
      format: 'epub',
      chapterCount: 1,
      direction: ReadingDirection.ltr,
    );
    await pumpShell(tester, books: [book]);

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, '删除书籍'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('book-book-delete')), findsNothing);
  });
}

class _FakeSettingsRepository extends SettingsRepository {
  _FakeSettingsRepository() : super(AppDatabase.inMemory());

  @override
  Future<BookReadingOverride?> loadBookOverride(String bookId) async => null;

  @override
  Future<void> saveBookOverride(BookReadingOverride override) async {}

  @override
  Future<void> clearBookOverride(String bookId) async {}
}

class _FakeBookmarkRepository extends BookmarkRepository {
  _FakeBookmarkRepository() : super(AppDatabase.inMemory());

  final _bookmarks = <Bookmark>[];

  @override
  Future<List<Bookmark>> listForBook(String bookId) async =>
      _bookmarks.where((bookmark) => bookmark.bookId == bookId).toList();

  @override
  Future<Bookmark> add({
    required String bookId,
    required String locator,
    required String chapterTitle,
    String? label,
  }) async {
    final bookmark = Bookmark(
      id: 'bookmark-${_bookmarks.length}',
      bookId: bookId,
      locator: locator,
      chapterTitle: chapterTitle,
      createdAt: DateTime(2026),
      label: label,
    );
    _bookmarks.add(bookmark);
    return bookmark;
  }

  @override
  Future<void> remove(String bookmarkId) async {
    _bookmarks.removeWhere((bookmark) => bookmark.id == bookmarkId);
  }
}

class _FakeBookRepository extends BookRepository {
  _FakeBookRepository([this._books = const []]) : super(AppDatabase.inMemory());

  final List<LibraryBook> _books;

  @override
  Future<List<LibraryBook>> listBooks() async => _books;

  @override
  Future<void> deleteBook(String bookId) async {
    _books.removeWhere((book) => book.id == bookId);
  }
}

class _FakeAnnotationRepository extends AnnotationRepository {
  _FakeAnnotationRepository() : super(AppDatabase.inMemory());

  @override
  Future<List<ReadingAnnotation>> listForBook(String bookId) async => const [];
}

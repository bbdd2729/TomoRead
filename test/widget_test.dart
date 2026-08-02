import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/app/appearance.dart';
import 'package:tomoread/app/providers.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/annotation_repository.dart';
import 'package:tomoread/data/repositories/bookmark_repository.dart';
import 'package:tomoread/data/repositories/book_repository.dart';
import 'package:tomoread/data/repositories/settings_repository.dart';
import 'package:tomoread/data/services/storage_diagnostics_service.dart';
import 'package:tomoread/domain/models/bookmark.dart';
import 'package:tomoread/domain/models/epub_manifest.dart';
import 'package:tomoread/domain/models/library_book.dart';
import 'package:tomoread/domain/models/reading_settings.dart';
import 'package:tomoread/domain/models/reading_annotation.dart';
import 'package:tomoread/features/library/book_details_page.dart';
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

  void configureMobile(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpShell(
    WidgetTester tester, {
    ValueChanged<AppAppearance>? onAppearanceChanged,
    List<LibraryBook> books = const [],
    bool includeStorageDiagnostics = false,
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
          if (includeStorageDiagnostics)
            storageDiagnosticsServiceProvider.overrideWithValue(
              StorageDiagnosticsService(
                rootProvider: () async => Directory(
                  '${Directory.systemTemp.path}${Platform.pathSeparator}'
                  'tomoread-widget-storage-missing',
                ),
              ),
            ),
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

  testWidgets('opens backup and storage tools from data settings', (
    tester,
  ) async {
    configureDesktop(tester);
    await pumpShell(tester, includeStorageDiagnostics: true);

    await tester.tap(find.byKey(const Key('settings-navigation')));
    await tester.pump();
    await tester.tap(find.text('数据与隐私'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const Key('create-library-backup')), findsOneWidget);
    expect(find.byKey(const Key('restore-library-backup')), findsOneWidget);
    expect(find.text('存储诊断'), findsOneWidget);
  });

  testWidgets('adds a bookmark and toggles the reader toc', (tester) async {
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
            initialControlsVisible: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('reader-progress-slider')), findsOneWidget);
    expect(find.textContaining('第 1 / 1 页'), findsNothing);
    expect(find.byKey(const Key('reader-position-label')), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-bookmark')));
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.bookmark), findsWidgets);

    await tester.tap(find.byKey(const Key('reader-toc')));
    await tester.pump();
    expect(find.byIcon(Icons.format_list_bulleted), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-focus-mode')));
    await tester.pump();
    final footerOpacity = tester.widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.byKey(const Key('reader-footer')),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );
    expect(footerOpacity.opacity, 0);
  });

  testWidgets('opens mobile reader navigation sheets', (tester) async {
    configureMobile(tester);
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
            initialControlsVisible: true,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader-toc')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('reader-mobile-toc-header')), findsOneWidget);

    await tester.tap(find.byKey(const Key('reader-mobile-toc-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('reader-side-panel')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('reader-mobile-side-header')), findsOneWidget);
    expect(find.byKey(const Key('reader-mobile-more')), findsOneWidget);
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

  testWidgets('switches between settings categories', (tester) async {
    configureDesktop(tester);
    await pumpShell(tester);

    await tester.tap(find.byKey(const Key('settings-navigation')));
    await tester.pump();
    await tester.tap(find.text('默认阅读'));
    await tester.pump();

    expect(find.text('默认书本字体'), findsOneWidget);
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
            readingSettings: ReadingSettings(
              layoutMode: ReaderLayoutMode.paginated,
              doubleColumn: false,
            ),
            initialControlsVisible: true,
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
    final doubleColumn = find.byKey(const Key('book-reading-double-column'));
    expect(doubleColumn, findsOneWidget);
    final doubleColumnTile = tester.widget<SwitchListTile>(doubleColumn);
    expect(doubleColumnTile.onChanged, isNotNull);
    doubleColumnTile.onChanged!(true);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(doubleColumn).value, isTrue);
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

  testWidgets('continue reading prefers the latest started book', (
    tester,
  ) async {
    configureDesktop(tester);
    final unreadImport = LibraryBook(
      id: 'unread-import',
      fileHash: 'unread-import',
      title: 'Recently imported',
      author: 'Author',
      filePath: 'C:/books/unread.epub',
      progress: 0,
      importedAt: DateTime(2026, 7),
      updatedAt: DateTime(2026, 7),
      format: 'epub',
      chapterCount: 5,
      direction: ReadingDirection.ltr,
    );
    final startedBook = LibraryBook(
      id: 'started-book',
      fileHash: 'started-book',
      title: 'Started book',
      author: 'Reader',
      filePath: 'C:/books/started.epub',
      progress: 0.4,
      importedAt: DateTime(2026, 1),
      updatedAt: DateTime(2026, 8),
      format: 'epub',
      chapterCount: 5,
      chapterIndex: 2,
      locator: 'epub:v3|2|0.25000||',
      direction: ReadingDirection.ltr,
    );

    await pumpShell(tester, books: [unreadImport, startedBook]);

    expect(
      find.byKey(const Key('continue-reading-started-book')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('continue-reading-unread-import')),
      findsNothing,
    );
  });

  testWidgets('filters by favorite, category, and tag and enters selection', (
    tester,
  ) async {
    configureDesktop(tester);
    final favorite = LibraryBook(
      id: 'favorite-book',
      fileHash: 'favorite-book',
      title: 'Dart Handbook',
      author: 'Alice',
      filePath: 'C:/books/dart.epub',
      progress: 0,
      importedAt: DateTime(2026),
      format: 'epub',
      chapterCount: 4,
      direction: ReadingDirection.ltr,
      category: 'Technology',
      tags: const ['Dart'],
      isFavorite: true,
    );
    final other = LibraryBook(
      id: 'other-book',
      fileHash: 'other-book',
      title: 'History Notes',
      author: 'Bob',
      filePath: 'C:/books/history.pdf',
      progress: 0,
      importedAt: DateTime(2025),
      format: 'pdf',
      chapterCount: 3,
      direction: ReadingDirection.ltr,
      category: 'History',
      tags: const ['Archive'],
    );
    await pumpShell(tester, books: [favorite, other]);

    await tester.tap(find.widgetWithText(FilterChip, '收藏'));
    await tester.pump();
    expect(find.byKey(const Key('book-favorite-book')), findsOneWidget);
    expect(find.byKey(const Key('book-other-book')), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, '收藏'));
    await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pump();
    await tester.tap(find.text('Technology').last);
    await tester.pump();
    expect(find.byKey(const Key('book-favorite-book')), findsOneWidget);
    expect(find.byKey(const Key('book-other-book')), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Dart'));
    await tester.pump();
    expect(find.byKey(const Key('book-favorite-book')), findsOneWidget);
    expect(find.byKey(const Key('book-other-book')), findsNothing);

    await tester.longPress(find.byKey(const Key('book-favorite-book')));
    await tester.pump();
    expect(find.byKey(const Key('library-selection-toolbar')), findsOneWidget);
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

    expect(find.byType(BookDetailsPage), findsOneWidget);
    await tester.tap(find.byKey(const Key('book-detail-read')));
    await tester.pump();

    expect(find.byType(ReaderWorkspace), findsOneWidget);
  });

  testWidgets('opens book details before the reader', (tester) async {
    configureDesktop(tester);
    final book = LibraryBook(
      id: 'detail-book',
      fileHash: 'detail-book',
      title: 'Book Detail Title',
      author: 'Detail Author',
      filePath: 'C:/books/detail.epub',
      progress: 0.35,
      importedAt: DateTime(2026),
      format: 'epub',
      chapterCount: 12,
      direction: ReadingDirection.ltr,
      description: 'A book description for the detail page.',
    );
    await pumpShell(tester, books: [book]);

    await tester.tap(find.byKey(const Key('book-detail-book')));
    await tester.pumpAndSettle();

    expect(find.byType(BookDetailsPage), findsOneWidget);
    expect(find.text('Book Detail Title'), findsWidgets);
    expect(find.text('Detail Author'), findsOneWidget);
    expect(
      find.text('A book description for the detail page.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('book-detail-cover')), findsOneWidget);
  });

  testWidgets('edits book metadata from the details page', (tester) async {
    configureDesktop(tester);
    final book = LibraryBook(
      id: 'editable-book',
      fileHash: 'editable-book',
      title: 'Original title',
      author: 'Original author',
      filePath: 'C:/books/editable.epub',
      progress: 0,
      importedAt: DateTime(2026),
      format: 'epub',
      chapterCount: 2,
      direction: ReadingDirection.ltr,
    );
    await pumpShell(tester, books: [book]);

    await tester.tap(find.byKey(const Key('book-editable-book')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-detail-edit')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('book-detail-title-input')),
      'Updated title',
    );
    await tester.tap(find.byKey(const Key('book-detail-save')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Updated title'), findsWidgets);
    expect(find.byKey(const Key('book-detail-favorite')), findsOneWidget);
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

  @override
  Future<void> updateMetadata({
    required String bookId,
    required String title,
    required String author,
    required String? description,
    required String? category,
    required List<String> tags,
  }) async {
    final index = _books.indexWhere((book) => book.id == bookId);
    if (index < 0) return;
    _books[index] = _books[index].copyWith(
      title: title,
      author: author,
      description: description ?? '',
      category: category ?? '',
      tags: tags,
      clearDescription: description == null,
      clearCategory: category == null,
    );
  }

  @override
  Future<void> setFavorite(String bookId, bool isFavorite) async {
    final index = _books.indexWhere((book) => book.id == bookId);
    if (index < 0) return;
    _books[index] = _books[index].copyWith(isFavorite: isFavorite);
  }

  @override
  Future<void> resetReadingPosition(String bookId) async {
    final index = _books.indexWhere((book) => book.id == bookId);
    if (index < 0) return;
    _books[index] = _books[index].copyWith(
      progress: 0,
      chapterIndex: 0,
      clearLocator: true,
    );
  }
}

class _FakeAnnotationRepository extends AnnotationRepository {
  _FakeAnnotationRepository() : super(AppDatabase.inMemory());

  @override
  Future<List<ReadingAnnotation>> listForBook(String bookId) async => const [];
}

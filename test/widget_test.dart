import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/app/appearance.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/bookmark_repository.dart';
import 'package:tomoread/data/repositories/book_repository.dart';
import 'package:tomoread/data/repositories/settings_repository.dart';
import 'package:tomoread/data/services/book_import_service.dart';
import 'package:tomoread/domain/models/bookmark.dart';
import 'package:tomoread/domain/models/library_book.dart';
import 'package:tomoread/domain/models/reading_settings.dart';
import 'package:tomoread/features/library/library_controller.dart';
import 'package:tomoread/features/reader/reader_workspace.dart';
import 'package:tomoread/features/workspace/app_shell.dart';

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
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          appearance: const AppAppearance(),
          readingSettings: const ReadingSettings(),
          settingsRepository: _FakeSettingsRepository(),
          bookmarkRepository: _FakeBookmarkRepository(),
          libraryController: _FakeLibraryController(),
          onAppearanceChanged: onAppearanceChanged ?? (_) {},
          onReadingSettingsChanged: (_) {},
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

  testWidgets('adds a bookmark and collapses the reader toc', (tester) async {
    configureDesktop(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderWorkspace(
          bookId: 'book-a',
          title: 'Test book',
          readingSettings: const ReadingSettings(),
          settingsRepository: _FakeSettingsRepository(),
          bookmarkRepository: _FakeBookmarkRepository(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('reader-bookmark')));
    await tester.pump();
    expect(find.byIcon(Icons.bookmark), findsWidgets);

    await tester.tap(find.byKey(const Key('reader-toc')));
    await tester.pump();
    expect(find.byIcon(Icons.menu_open), findsOneWidget);
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

class _FakeLibraryController extends LibraryController {
  _FakeLibraryController()
    : super(
        repository: _FakeBookRepository(),
        importService: BookImportService(repository: _FakeBookRepository()),
      );
}

class _FakeBookRepository extends BookRepository {
  _FakeBookRepository() : super(AppDatabase.inMemory());

  @override
  Future<List<LibraryBook>> listBooks() async => const [];
}

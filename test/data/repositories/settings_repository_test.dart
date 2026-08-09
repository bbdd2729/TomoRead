import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/app/appearance.dart';
import 'package:tomoread/data/database/app_database.dart';
import 'package:tomoread/data/repositories/annotation_repository.dart';
import 'package:tomoread/data/repositories/bookmark_repository.dart';
import 'package:tomoread/data/repositories/book_repository.dart';
import 'package:tomoread/data/repositories/settings_repository.dart';
import 'package:tomoread/domain/models/epub_manifest.dart';
import 'package:tomoread/domain/models/font_choice.dart';
import 'package:tomoread/domain/models/library_book.dart';
import 'package:tomoread/domain/models/reading_font.dart';
import 'package:tomoread/domain/models/reading_settings.dart';
import 'package:tomoread/domain/models/reading_annotation.dart';
import 'package:tomoread/domain/models/reader_theme.dart';
import 'package:tomoread/domain/models/library_workspace_state.dart';

void main() {
  late AppDatabase database;
  late SettingsRepository settings;
  late BookmarkRepository bookmarks;
  late AnnotationRepository annotations;
  late BookRepository books;

  setUp(() {
    database = AppDatabase.inMemory();
    settings = SettingsRepository(database);
    bookmarks = BookmarkRepository(database);
    annotations = AnnotationRepository(database);
    books = BookRepository(database);
  });

  tearDown(() => database.close());

  test('persists app, global reading, and per-book settings', () async {
    await settings.saveAppearance(
      const AppAppearance(
        mode: ThemeMode.dark,
        seed: ThemeSeed.green,
        themeStyle: AppThemeStyle.paper,
        textScale: 1.25,
        uiFont: FontChoice.monospace,
        desktopNavigationWidth: 288,
        desktopNavigationCollapsed: true,
        readerTocWidth: 336,
        readerSidePanelWidth: 384,
        readerTocVisible: false,
        readerSidePanelVisible: false,
      ),
    );
    await settings.saveReadingSettings(
      const ReadingSettings(
        font: ReadingFontRef.serif,
        fontSize: 22,
        lineHeight: 2.1,
        pageMargin: 40,
        doubleColumn: false,
        layoutMode: ReaderLayoutMode.paginated,
        tapToTurnPages: true,
        volumeKeyTurnsPage: true,
        theme: ReaderThemeSelection(preset: ReaderThemePreset.paper),
      ),
    );
    await settings.saveBookOverride(
      const BookReadingOverride(
        bookId: 'book-a',
        settings: ReadingSettings(
          font: ReadingFontRef.monospace,
          fontSize: 18,
          pageMargin: 48,
          doubleColumn: false,
          layoutMode: ReaderLayoutMode.paginated,
          tapToTurnPages: true,
          theme: ReaderThemeSelection(
            preset: ReaderThemePreset.custom,
            customThemeId: 'night-ink',
          ),
        ),
      ),
    );

    final stored = await settings.load();
    final override = await settings.loadBookOverride('book-a');

    expect(stored.appearance.mode, ThemeMode.dark);
    expect(stored.appearance.seed, ThemeSeed.green);
    expect(stored.appearance.themeStyle, AppThemeStyle.paper);
    expect(stored.appearance.uiFont, FontChoice.monospace);
    expect(stored.appearance.desktopNavigationWidth, 288);
    expect(stored.appearance.desktopNavigationCollapsed, isTrue);
    expect(stored.appearance.readerTocWidth, 336);
    expect(stored.appearance.readerSidePanelWidth, 384);
    expect(stored.appearance.readerTocVisible, isFalse);
    expect(stored.appearance.readerSidePanelVisible, isFalse);
    expect(stored.readingSettings.font, ReadingFontRef.serif);
    expect(stored.readingSettings.doubleColumn, isFalse);
    expect(stored.readingSettings.layoutMode, ReaderLayoutMode.paginated);
    expect(stored.readingSettings.tapToTurnPages, isTrue);
    expect(stored.readingSettings.volumeKeyTurnsPage, isTrue);
    expect(stored.readingSettings.theme.preset, ReaderThemePreset.paper);
    expect(override?.settings.font, ReadingFontRef.monospace);
    expect(override?.settings.fontSize, 18);
    expect(override?.settings.pageMargin, 48);
    expect(override?.settings.doubleColumn, isFalse);
    expect(override?.settings.layoutMode, ReaderLayoutMode.paginated);
    expect(override?.settings.tapToTurnPages, isTrue);
    expect(override?.settings.theme.preset, ReaderThemePreset.custom);
    expect(override?.settings.theme.customThemeId, 'night-ink');

    await settings.clearBookOverride('book-a');
    expect(await settings.loadBookOverride('book-a'), isNull);
  });

  test(
    'persists library workspace state independently from app settings',
    () async {
      const workspace = LibraryWorkspaceState(
        formatFilter: LibraryFormatFilter.text,
        sort: LibrarySort.progress,
        viewMode: LibraryViewMode.list,
        category: 'Markdown',
        tag: 'reference',
        favoritesOnly: true,
      );

      await settings.saveLibraryWorkspaceState(workspace);

      expect(await settings.loadLibraryWorkspaceState(), workspace);
    },
  );

  test(
    'persists custom reader themes and ignores invalid stored entries',
    () async {
      const customTheme = CustomReaderTheme(
        id: 'night-ink',
        name: '夜墨',
        backgroundArgb: 0xFF101418,
        foregroundArgb: 0xFFE4E7EA,
        accentArgb: 0xFF74B9A8,
      );

      await settings.saveCustomReaderThemes([customTheme]);
      final saved = await settings.loadCustomReaderThemes();
      expect(saved, hasLength(1));
      expect(saved.single.id, customTheme.id);
      expect(saved.single.name, customTheme.name);
      expect(saved.single.backgroundArgb, customTheme.backgroundArgb);

      final rawDatabase = await database.database;
      await rawDatabase.update(
        'app_settings',
        {
          'setting_value':
              '[{"id":"valid","name":"有效","backgroundArgb":1,"foregroundArgb":2,"accentArgb":3},{}]',
        },
        where: 'setting_key = ?',
        whereArgs: ['reader_custom_themes'],
      );

      final loaded = await settings.loadCustomReaderThemes();
      expect(loaded, hasLength(1));
      expect(loaded.single.name, '有效');

      await rawDatabase.update(
        'app_settings',
        {'setting_value': '{not-json'},
        where: 'setting_key = ?',
        whereArgs: ['reader_custom_themes'],
      );
      expect(await settings.loadCustomReaderThemes(), isEmpty);
    },
  );

  test('stores and removes bookmarks per book', () async {
    final first = await bookmarks.add(
      bookId: 'book-a',
      locator: 'chapter-2:start',
      chapterTitle: 'Chapter 2',
    );
    await bookmarks.add(
      bookId: 'book-b',
      locator: 'chapter-1:start',
      chapterTitle: 'Chapter 1',
    );

    final bookABookmarks = await bookmarks.listForBook('book-a');
    expect(bookABookmarks, hasLength(1));
    expect(bookABookmarks.single.id, first.id);

    await bookmarks.remove(first.id);
    expect(await bookmarks.listForBook('book-a'), isEmpty);
    expect(await bookmarks.listForBook('book-b'), hasLength(1));
  });

  test('stores annotations with their text location and note', () async {
    final rawDatabase = await database.database;
    await rawDatabase.insert('books', {
      'id': 'book-a',
      'title': 'Book',
      'author': '',
      'progress': 0,
      'chapter_index': 0,
      'chapter_count': 1,
      'read_direction': 'ltr',
      'created_at': DateTime(2026).millisecondsSinceEpoch,
      'updated_at': DateTime(2026).millisecondsSinceEpoch,
    });
    final annotation = await annotations.add(
      bookId: 'book-a',
      href: 'OPS/chapter-1.xhtml',
      locator: '12:34',
      selectedText: '真正的阅读',
      color: AnnotationColor.yellow,
      note: '保留这个观点。',
    );

    final stored = await annotations.listForBook('book-a');
    expect(stored, hasLength(1));
    expect(stored.single.id, annotation.id);
    expect(stored.single.locator, '12:34');

    await annotations.updateNote(annotation.id, 'updated note');
    expect(
      (await annotations.listForBook('book-a')).single.note,
      'updated note',
    );

    await annotations.updateNote(annotation.id, '   ');
    expect((await annotations.listForBook('book-a')).single.note, isNull);
    expect(stored.single.note, '保留这个观点。');

    await annotations.remove(annotation.id);
    expect(await annotations.listForBook('book-a'), isEmpty);
  });

  test('stores imported books with their EPUB manifest', () async {
    const manifest = EpubManifest(
      opfPath: 'OPS/content.opf',
      version: '3.0',
      direction: ReadingDirection.ltr,
      spine: [
        EpubSpineItem(
          id: 'chapter-1',
          href: 'OPS/chapter-1.xhtml',
          linear: true,
        ),
      ],
      toc: [
        EpubTocItem(
          title: 'Chapter 1',
          href: 'OPS/chapter-1.xhtml',
          spineIndex: 0,
        ),
      ],
    );
    final book = LibraryBook(
      id: 'hash-a',
      fileHash: 'hash-a',
      title: 'Imported book',
      author: 'Author',
      filePath: 'C:/books/hash-a.epub',
      progress: 0,
      importedAt: DateTime(2026),
      format: 'epub',
      chapterCount: 1,
      direction: ReadingDirection.ltr,
    );

    await books.saveImportedBook(ImportedBook(book: book, manifest: manifest));

    final stored = await books.listBooks();
    expect(stored, hasLength(1));
    expect(stored.single.title, 'Imported book');
    expect(stored.single.fileHash, 'hash-a');
    expect(
      (await books.loadManifest('hash-a'))?.spine.single.href,
      'OPS/chapter-1.xhtml',
    );

    await books.updateReadingPosition(
      bookId: 'hash-a',
      chapterIndex: 0,
      progress: 0.75,
      locator: '0:0.75000',
    );
    final updated = await books.findById('hash-a');
    expect(updated?.chapterIndex, 0);
    expect(updated?.progress, 0.75);
    expect(updated?.locator, '0:0.75000');
  });

  test('stores imported PDF books without an EPUB manifest', () async {
    final pdf = LibraryBook(
      id: 'pdf-a',
      fileHash: 'pdf-a',
      title: 'PDF book',
      author: '',
      filePath: 'C:/books/pdf-a.pdf',
      progress: 0.25,
      importedAt: DateTime(2026),
      format: 'pdf',
      chapterCount: 24,
      chapterIndex: 5,
      direction: ReadingDirection.ltr,
    );

    await books.saveImportedPdfBook(pdf);

    final stored = await books.findById('pdf-a');
    expect(stored?.format, 'pdf');
    expect(stored?.chapterCount, 24);
    expect(stored?.chapterIndex, 5);
    expect(await books.loadManifest('pdf-a'), isNull);
  });
}

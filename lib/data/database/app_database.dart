import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  AppDatabase({
    DatabaseFactory? databaseFactory,
    Future<String> Function()? pathProvider,
  }) : _databaseFactory = databaseFactory ?? _platformDatabaseFactory,
       _pathProvider = pathProvider ?? _defaultPath;

  AppDatabase.inMemory()
    : _databaseFactory = databaseFactoryFfi,
      _pathProvider = (() async => inMemoryDatabasePath);

  final DatabaseFactory _databaseFactory;
  final Future<String> Function() _pathProvider;
  Future<Database>? _database;

  Future<Database> get database => _database ??= _open();

  Future<void> close() async {
    final database = _database;
    if (database == null) return;
    await (await database).close();
    _database = null;
  }

  Future<Database> _open() async {
    final databasePath = await _pathProvider();
    return _databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 10,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
        onCreate: (database, version) => _createSchema(database),
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _upgradeToVersion2(database);
          }
          if (oldVersion < 3) {
            await _upgradeToVersion3(database);
          }
          if (oldVersion < 4) {
            await _upgradeToVersion4(database);
          }
          if (oldVersion < 5) {
            await _upgradeToVersion5(database);
          }
          if (oldVersion < 6) {
            await _upgradeToVersion6(database);
          }
          if (oldVersion < 7) {
            await _upgradeToVersion7(database);
          }
          if (oldVersion < 8) {
            await _upgradeToVersion8(database);
          }
          if (oldVersion < 9) {
            await _upgradeToVersion9(database);
          }
          if (oldVersion < 10) {
            await _upgradeToVersion10(database);
          }
        },
      ),
    );
  }

  static DatabaseFactory get _platformDatabaseFactory {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }
    return sqflite.databaseFactory;
  }

  Future<void> _createSchema(Database database) async {
    await database.execute('''
            CREATE TABLE app_settings (
              setting_key TEXT PRIMARY KEY,
              setting_value TEXT NOT NULL
            )
          ''');
    await database.execute('''
            CREATE TABLE books (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT NOT NULL DEFAULT '',
              file_hash TEXT UNIQUE,
              file_path TEXT,
              cover_path TEXT,
              format TEXT,
              description TEXT,
              progress REAL NOT NULL DEFAULT 0,
              locator TEXT,
              chapter_index INTEGER NOT NULL DEFAULT 0,
              chapter_count INTEGER NOT NULL DEFAULT 0,
              epub_version TEXT,
              read_direction TEXT NOT NULL DEFAULT 'ltr',
              category TEXT,
              tags_json TEXT NOT NULL DEFAULT '[]',
              is_favorite INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
    await _createBooksIndexes(database);
    await database.execute('''
            CREATE TABLE book_reading_overrides (
              book_id TEXT PRIMARY KEY,
              font TEXT NOT NULL,
              font_size REAL NOT NULL,
              line_height REAL NOT NULL,
              page_margin REAL NOT NULL,
              double_column INTEGER NOT NULL,
              layout_mode TEXT NOT NULL DEFAULT 'scroll',
              page_transition TEXT NOT NULL DEFAULT 'slide',
              tap_to_turn_pages INTEGER NOT NULL DEFAULT 0,
              updated_at INTEGER NOT NULL
            )
          ''');
    await database.execute('''
            CREATE TABLE bookmarks (
              id TEXT PRIMARY KEY,
              book_id TEXT NOT NULL,
              locator TEXT NOT NULL,
              chapter_title TEXT NOT NULL,
              label TEXT,
              created_at INTEGER NOT NULL,
              UNIQUE(book_id, locator)
            )
          ''');
    await database.execute(
      'CREATE INDEX bookmarks_book_id ON bookmarks(book_id)',
    );
    await database.execute('''
            CREATE TABLE book_manifests (
              book_id TEXT PRIMARY KEY,
              manifest_json TEXT NOT NULL,
              updated_at INTEGER NOT NULL,
              FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
            )
          ''');
    await _createAnnotationsTable(database);
    await _createChatTables(database);
    await _createAnnotationTagsTable(database);
    await _createReadingSessionsTable(database);
  }

  Future<void> _upgradeToVersion2(Database database) async {
    await database.execute('ALTER TABLE books ADD COLUMN file_hash TEXT');
    await database.execute('ALTER TABLE books ADD COLUMN cover_path TEXT');
    await database.execute('ALTER TABLE books ADD COLUMN description TEXT');
    await database.execute(
      'ALTER TABLE books ADD COLUMN chapter_index INTEGER NOT NULL DEFAULT 0',
    );
    await database.execute(
      'ALTER TABLE books ADD COLUMN chapter_count INTEGER NOT NULL DEFAULT 0',
    );
    await database.execute('ALTER TABLE books ADD COLUMN epub_version TEXT');
    await database.execute(
      "ALTER TABLE books ADD COLUMN read_direction TEXT NOT NULL DEFAULT 'ltr'",
    );
    await database.execute(
      'CREATE UNIQUE INDEX books_file_hash ON books(file_hash)',
    );
    await database.execute('''
      CREATE TABLE book_manifests (
        book_id TEXT PRIMARY KEY,
        manifest_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _upgradeToVersion3(Database database) =>
      _createAnnotationsTable(database);

  Future<void> _upgradeToVersion4(Database database) => database.execute(
    "ALTER TABLE book_reading_overrides ADD COLUMN layout_mode TEXT NOT NULL DEFAULT 'scroll'",
  );

  Future<void> _upgradeToVersion5(Database database) async {
    await database.execute('ALTER TABLE books ADD COLUMN category TEXT');
    await database.execute(
      "ALTER TABLE books ADD COLUMN tags_json TEXT NOT NULL DEFAULT '[]'",
    );
    await database.execute(
      'ALTER TABLE books ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0',
    );
    await _createBooksIndexes(database);
  }

  Future<void> _upgradeToVersion6(Database database) => database.execute(
    "ALTER TABLE book_reading_overrides ADD COLUMN page_transition TEXT NOT NULL DEFAULT 'slide'",
  );

  Future<void> _upgradeToVersion7(Database database) => database.execute(
    'ALTER TABLE book_reading_overrides ADD COLUMN tap_to_turn_pages INTEGER NOT NULL DEFAULT 0',
  );

  Future<void> _upgradeToVersion8(Database database) =>
      _createChatTables(database);

  Future<void> _upgradeToVersion9(Database database) async {
    await _addColumnIfMissing(
      database,
      table: 'reading_annotations',
      column: 'updated_at',
      definition: 'INTEGER',
    );
    await _addColumnIfMissing(
      database,
      table: 'reading_annotations',
      column: 'chapter_index',
      definition: 'INTEGER',
    );
    await _addColumnIfMissing(
      database,
      table: 'reading_annotations',
      column: 'chapter_title',
      definition: 'TEXT',
    );
    await database.execute('''
      UPDATE reading_annotations
      SET updated_at = created_at
      WHERE updated_at IS NULL
    ''');
    await _createAnnotationTagsTable(database);
  }

  Future<void> _addColumnIfMissing(
    Database database, {
    required String table,
    required String column,
    required String definition,
  }) async {
    final columns = await database.rawQuery('PRAGMA table_info($table)');
    if (columns.any((row) => row['name'] == column)) return;
    await database.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  Future<void> _upgradeToVersion10(Database database) =>
      _createReadingSessionsTable(database);

  Future<void> _createBooksIndexes(Database database) async {
    await database.execute(
      'CREATE INDEX IF NOT EXISTS books_category ON books(category)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS books_is_favorite ON books(is_favorite)',
    );
  }

  Future<void> _createAnnotationsTable(Database database) async {
    await database.execute('''
      CREATE TABLE reading_annotations (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        href TEXT NOT NULL,
        locator TEXT NOT NULL,
        selected_text TEXT NOT NULL,
        note TEXT,
        color TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        chapter_index INTEGER,
        chapter_title TEXT,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');
    await database.execute(
      'CREATE INDEX reading_annotations_book_id ON reading_annotations(book_id)',
    );
    await database.execute(
      'CREATE INDEX reading_annotations_created ON reading_annotations(created_at DESC, id DESC)',
    );
    await database.execute(
      'CREATE INDEX reading_annotations_book_updated ON reading_annotations(book_id, updated_at DESC, id DESC)',
    );
  }

  Future<void> _createAnnotationTagsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS annotation_tags (
        annotation_id TEXT NOT NULL,
        normalized_tag TEXT NOT NULL,
        display_tag TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        PRIMARY KEY(annotation_id, normalized_tag),
        FOREIGN KEY(annotation_id) REFERENCES reading_annotations(id) ON DELETE CASCADE
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS annotation_tags_tag ON annotation_tags(normalized_tag)',
    );
  }

  Future<void> _createChatTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS ai_provider_profiles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        protocol TEXT NOT NULL,
        base_url TEXT NOT NULL,
        model_id TEXT NOT NULL,
        secret_key_id TEXT NOT NULL,
        temperature REAL NOT NULL DEFAULT 0.3,
        max_output_tokens INTEGER NOT NULL DEFAULT 2048,
        is_active INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS chat_threads (
        id TEXT PRIMARY KEY,
        scope TEXT NOT NULL CHECK(scope IN ('general', 'book')),
        book_id TEXT,
        title TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE SET NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS chat_threads_scope_updated
      ON chat_threads(scope, book_id, updated_at DESC)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        id TEXT PRIMARY KEY,
        thread_id TEXT NOT NULL,
        role TEXT NOT NULL CHECK(role IN ('system', 'user', 'assistant')),
        content TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL CHECK(status IN ('complete', 'streaming', 'failed', 'cancelled')),
        model_id TEXT,
        error_code TEXT,
        created_at INTEGER NOT NULL,
        completed_at INTEGER,
        FOREIGN KEY(thread_id) REFERENCES chat_threads(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS chat_messages_thread_created
      ON chat_messages(thread_id, created_at ASC)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS chat_message_citations (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        ordinal INTEGER NOT NULL,
        book_id TEXT NOT NULL,
        href TEXT NOT NULL,
        locator TEXT NOT NULL,
        chapter_index INTEGER,
        chapter_title TEXT,
        quote TEXT NOT NULL,
        FOREIGN KEY(message_id) REFERENCES chat_messages(id) ON DELETE CASCADE,
        UNIQUE(message_id, ordinal)
      )
    ''');
  }

  Future<void> _createReadingSessionsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS reading_sessions (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        session_group_id TEXT NOT NULL,
        format TEXT NOT NULL CHECK(format IN ('epub', 'pdf')),
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        active_millis INTEGER NOT NULL DEFAULT 0,
        timezone_offset_minutes INTEGER NOT NULL,
        progress_start REAL NOT NULL,
        progress_end REAL NOT NULL,
        locator_start TEXT,
        locator_end TEXT,
        interaction_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE,
        CHECK(progress_start >= 0 AND progress_start <= 1),
        CHECK(progress_end >= 0 AND progress_end <= 1)
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS reading_sessions_time ON reading_sessions(started_at, ended_at)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS reading_sessions_book_time ON reading_sessions(book_id, started_at DESC)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS reading_sessions_group_time ON reading_sessions(session_group_id, started_at ASC)',
    );
  }

  static Future<String> _defaultPath() async {
    final directory = await getApplicationSupportDirectory();
    final databaseDirectory = Directory(path.join(directory.path, 'database'));
    if (!await databaseDirectory.exists()) {
      await databaseDirectory.create(recursive: true);
    }
    return path.join(databaseDirectory.path, 'tomoread.db');
  }
}

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
       _pathProvider = pathProvider ?? _defaultPath,
       _singleInstance = true;

  AppDatabase.inMemory()
    : _databaseFactory = databaseFactoryFfi,
      _pathProvider = (() async => inMemoryDatabasePath),
      _singleInstance = false;

  final DatabaseFactory _databaseFactory;
  final Future<String> Function() _pathProvider;
  final bool _singleInstance;
  Future<Database>? _database;

  static const schemaVersion = 23;

  Future<Database> get database => _database ??= _open();

  Future<String> get databasePath => _pathProvider();

  Future<void> createSnapshot(String destinationPath) async {
    final destination = File(destinationPath);
    await destination.parent.create(recursive: true);
    if (await destination.exists()) await destination.delete();
    final escapedPath = destination.path.replaceAll("'", "''");
    await (await database).execute("VACUUM INTO '$escapedPath'");
  }

  Future<DatabaseSnapshotInfo> inspectSnapshot(String snapshotPath) async {
    final snapshotFile = File(snapshotPath);
    if (!await snapshotFile.exists()) {
      throw const FormatException('数据库快照不存在。');
    }
    Database? snapshot;
    try {
      snapshot = await _databaseFactory.openDatabase(
        snapshotFile.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final integrityRows = await snapshot.rawQuery('PRAGMA quick_check');
      final integrity = integrityRows.isEmpty
          ? null
          : integrityRows.first.values.first.toString();
      if (integrity != 'ok') {
        throw const FormatException('数据库完整性校验失败。');
      }
      final versionRows = await snapshot.rawQuery('PRAGMA user_version');
      final version = versionRows.isEmpty
          ? null
          : versionRows.first.values.first;
      if (version is! int || version <= 0) {
        throw const FormatException('数据库 schema 版本无效。');
      }
      final booksTable = await snapshot.rawQuery('''
        SELECT name FROM sqlite_master
        WHERE type = 'table' AND name = 'books'
      ''');
      if (booksTable.isEmpty) {
        throw const FormatException('数据库缺少书库表。');
      }
      final bookRows = await snapshot.query('books', columns: ['id']);
      final fontRows = await snapshot.query(
        'imported_fonts',
        columns: ['id'],
      );
      return DatabaseSnapshotInfo(
        schemaVersion: version,
        bookIds: bookRows.map((row) => row['id']! as String).toSet(),
        fontIds: fontRows.map((row) => row['id']! as String).toSet(),
      );
    } finally {
      await snapshot?.close();
    }
  }

  Future<void> prepareSnapshotForBackup({
    required String snapshotPath,
    required Map<String, String> bookPaths,
    required Map<String, String> coverPaths,
    required Map<String, String> fontPaths,
  }) async {
    Database? snapshot;
    try {
      snapshot = await _databaseFactory.openDatabase(
        snapshotPath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await snapshot.transaction((transaction) async {
        final books = await transaction.query('books', columns: ['id']);
        for (final row in books) {
          final id = row['id']! as String;
          await transaction.update(
            'books',
            {
              'file_path': bookPaths[id] == null
                  ? null
                  : 'backup://${bookPaths[id]}',
              'cover_path': coverPaths[id] == null
                  ? null
                  : 'backup://${coverPaths[id]}',
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
        final fonts = await transaction.query(
          'imported_fonts',
          columns: ['id'],
        );
        for (final row in fonts) {
          final id = row['id']! as String;
          await transaction.update(
            'imported_fonts',
            {
              'file_path': fontPaths[id] == null
                  ? 'backup://unavailable/$id'
                  : 'backup://${fontPaths[id]}',
              'source': 'backup',
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      });
    } finally {
      await snapshot?.close();
    }
  }

  Future<void> rewriteManagedPaths({
    required Directory supportRoot,
    required Map<String, String> bookPaths,
    required Map<String, String> coverPaths,
    required Map<String, String> fontPaths,
  }) async {
    final root = path.normalize(supportRoot.path);
    final liveDatabase = await database;
    await liveDatabase.transaction((transaction) async {
      for (final entry in bookPaths.entries) {
        final target = path.normalize(path.join(root, entry.value));
        if (!path.isWithin(root, target)) {
          throw const FormatException('书籍恢复路径越界。');
        }
        await transaction.update(
          'books',
          {'file_path': target},
          where: 'id = ?',
          whereArgs: [entry.key],
        );
      }
      for (final entry in coverPaths.entries) {
        final target = path.normalize(path.join(root, entry.value));
        if (!path.isWithin(root, target)) {
          throw const FormatException('封面恢复路径越界。');
        }
        await transaction.update(
          'books',
          {'cover_path': target},
          where: 'id = ?',
          whereArgs: [entry.key],
        );
      }
      for (final entry in fontPaths.entries) {
        final target = path.normalize(path.join(root, entry.value));
        if (!path.isWithin(root, target)) {
          throw const FormatException('字体恢复路径越界。');
        }
        await transaction.update(
          'imported_fonts',
          {'file_path': target, 'source': 'restored-backup'},
          where: 'id = ?',
          whereArgs: [entry.key],
        );
      }
    });
  }

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
        version: schemaVersion,
        singleInstance: _singleInstance,
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
          if (oldVersion < 11) {
            await _upgradeToVersion11(database);
          }
          if (oldVersion < 12) {
            await _upgradeToVersion12(database);
          }
          if (oldVersion < 13) {
            await _upgradeToVersion13(database);
          }
          if (oldVersion < 14) {
            await _upgradeToVersion14(database);
          }
          if (oldVersion < 15) {
            await _upgradeToVersion15(database);
          }
          if (oldVersion < 16) {
            await _upgradeToVersion16(database);
          }
          if (oldVersion < 17) {
            await _upgradeToVersion17(database);
          }
          if (oldVersion < 18) {
            await _upgradeToVersion18(database);
          }
          if (oldVersion < 19) {
            await _upgradeToVersion19(database);
          }
          if (oldVersion < 20) {
            await _upgradeToVersion20(database);
          }
          if (oldVersion < 21) {
            await _upgradeToVersion21(database);
          }
          if (oldVersion < 22) {
            await _upgradeToVersion22(database);
          }
          if (oldVersion < 23) {
            await _upgradeToVersion23(database);
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
              setting_value TEXT NOT NULL,
              updated_at INTEGER NOT NULL DEFAULT 0,
              sync_revision INTEGER NOT NULL DEFAULT 1
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
              updated_at INTEGER NOT NULL,
              sync_revision INTEGER NOT NULL DEFAULT 1
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
              updated_at INTEGER NOT NULL,
              sync_revision INTEGER NOT NULL DEFAULT 1
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
              updated_at INTEGER NOT NULL DEFAULT 0,
              sync_revision INTEGER NOT NULL DEFAULT 1,
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
    await _createAiAgentTables(database);
    await _createAnnotationTagsTable(database);
    await _createReadingSessionsTable(database);
    await _createTextColoringTables(database);
    await _createPomodoroSessionsTable(database);
    await _createTextContentTables(database);
    await _createImportedFontsTable(database);
    await _createTextProjectionTables(database);
    await _createContentChunkTables(database);
    await _createEmbeddingTables(database);
    await _createVisualArtifactTables(database);
    await _createSyncTables(database);
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

  Future<void> _upgradeToVersion11(Database database) async {
    await _addColumnIfMissing(
      database,
      table: 'ai_provider_profiles',
      column: 'enable_tools',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      database,
      table: 'ai_provider_profiles',
      column: 'enable_reasoning',
      definition: 'INTEGER NOT NULL DEFAULT 1',
    );
    for (final column in const [
      ('input_tokens', 'INTEGER'),
      ('output_tokens', 'INTEGER'),
      ('reasoning_tokens', 'INTEGER'),
      ('cached_tokens', 'INTEGER'),
      ('stop_reason', 'TEXT'),
    ]) {
      await _addColumnIfMissing(
        database,
        table: 'chat_messages',
        column: column.$1,
        definition: column.$2,
      );
    }
    await _createAiAgentTables(database);
    await database.execute('''
      INSERT OR IGNORE INTO chat_message_parts (
        id, message_id, ordinal, type, status, text_content,
        payload_json, provider_item_id, created_at, updated_at
      )
      SELECT
        'legacy-text-' || id,
        id,
        0,
        'text',
        CASE WHEN status = 'streaming' THEN 'running' ELSE 'completed' END,
        content,
        NULL,
        NULL,
        created_at,
        COALESCE(completed_at, created_at)
      FROM chat_messages
      WHERE content <> ''
    ''');
  }

  Future<void> _upgradeToVersion12(Database database) =>
      _createTextColoringTables(database);

  Future<void> _upgradeToVersion13(Database database) => _addColumnIfMissing(
    database,
    table: 'reading_annotations',
    column: 'render_style',
    definition: "TEXT NOT NULL DEFAULT 'highlight'",
  );

  Future<void> _upgradeToVersion14(Database database) =>
      _createPomodoroSessionsTable(database);

  Future<void> _upgradeToVersion15(Database database) async {
    for (final column in const [
      ('preset_id', 'TEXT'),
      ('auth_type', "TEXT NOT NULL DEFAULT 'bearer'"),
      ('capabilities_json', "TEXT NOT NULL DEFAULT '{}'"),
      ('custom_headers_secret_id', 'TEXT'),
      ('is_enabled', 'INTEGER NOT NULL DEFAULT 1'),
    ]) {
      await _addColumnIfMissing(
        database,
        table: 'ai_provider_profiles',
        column: column.$1,
        definition: column.$2,
      );
    }
  }

  Future<void> _upgradeToVersion16(Database database) =>
      _createTextContentTables(database);

  Future<void> _upgradeToVersion17(Database database) async {
    final tables = await database.rawQuery('''
      SELECT name FROM sqlite_master
      WHERE type = 'table' AND name = 'reading_sessions'
    ''');
    if (tables.isEmpty) {
      await _createReadingSessionsTable(database);
      return;
    }
    await database.execute(
      'ALTER TABLE reading_sessions RENAME TO reading_sessions_v16',
    );
    for (final index in const [
      'reading_sessions_time',
      'reading_sessions_book_time',
      'reading_sessions_group_time',
    ]) {
      await database.execute('DROP INDEX IF EXISTS $index');
    }
    await _createReadingSessionsTable(database);
    await database.execute('''
      INSERT INTO reading_sessions (
        id, book_id, session_group_id, format, started_at, ended_at,
        active_millis, timezone_offset_minutes, progress_start, progress_end,
        locator_start, locator_end, interaction_count, created_at, updated_at
      )
      SELECT
        id, book_id, session_group_id, format, started_at, ended_at,
        active_millis, timezone_offset_minutes, progress_start, progress_end,
        locator_start, locator_end, interaction_count, created_at, updated_at
      FROM reading_sessions_v16
    ''');
    await database.execute('DROP TABLE reading_sessions_v16');
  }

  Future<void> _upgradeToVersion18(Database database) =>
      _createImportedFontsTable(database);

  Future<void> _upgradeToVersion19(Database database) =>
      _createTextProjectionTables(database);

  Future<void> _upgradeToVersion20(Database database) =>
      _createContentChunkTables(database);

  Future<void> _upgradeToVersion21(Database database) =>
      _createVisualArtifactTables(database);

  Future<void> _upgradeToVersion22(Database database) async {
    final tableRows = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final tables = tableRows
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();
    for (final column in const [
      ('books', 'sync_revision', 'INTEGER NOT NULL DEFAULT 1'),
      ('bookmarks', 'updated_at', 'INTEGER NOT NULL DEFAULT 0'),
      ('bookmarks', 'sync_revision', 'INTEGER NOT NULL DEFAULT 1'),
      ('reading_annotations', 'sync_revision', 'INTEGER NOT NULL DEFAULT 1'),
      ('annotation_tags', 'updated_at', 'INTEGER NOT NULL DEFAULT 0'),
      ('annotation_tags', 'sync_revision', 'INTEGER NOT NULL DEFAULT 1'),
      ('app_settings', 'updated_at', 'INTEGER NOT NULL DEFAULT 0'),
      ('app_settings', 'sync_revision', 'INTEGER NOT NULL DEFAULT 1'),
      ('book_reading_overrides', 'sync_revision', 'INTEGER NOT NULL DEFAULT 1'),
      ('text_display_rules', 'sync_revision', 'INTEGER NOT NULL DEFAULT 1'),
      (
        'book_text_projection_settings',
        'sync_revision',
        'INTEGER NOT NULL DEFAULT 1',
      ),
      ('chat_threads', 'sync_revision', 'INTEGER NOT NULL DEFAULT 1'),
      ('chat_messages', 'updated_at', 'INTEGER NOT NULL DEFAULT 0'),
      ('chat_messages', 'sync_revision', 'INTEGER NOT NULL DEFAULT 1'),
      ('imported_fonts', 'updated_at', 'INTEGER NOT NULL DEFAULT 0'),
      ('imported_fonts', 'sync_revision', 'INTEGER NOT NULL DEFAULT 1'),
    ]) {
      if (!tables.contains(column.$1)) continue;
      await _addColumnIfMissing(
        database,
        table: column.$1,
        column: column.$2,
        definition: column.$3,
      );
    }
    if (tables.contains('bookmarks')) {
      await database.execute(
        'UPDATE bookmarks SET updated_at = created_at WHERE updated_at = 0',
      );
    }
    if (tables.contains('annotation_tags')) {
      await database.execute(
        'UPDATE annotation_tags SET updated_at = created_at WHERE updated_at = 0',
      );
    }
    if (tables.contains('chat_messages')) {
      await database.execute('''
        UPDATE chat_messages
        SET updated_at = COALESCE(completed_at, created_at)
        WHERE updated_at = 0
      ''');
    }
    if (tables.contains('imported_fonts')) {
      await database.execute(
        'UPDATE imported_fonts SET updated_at = created_at WHERE updated_at = 0',
      );
    }
    await _createSyncTables(database);
  }

  Future<void> _upgradeToVersion23(Database database) =>
      _createEmbeddingTables(database);

  Future<void> _createEmbeddingTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS embedding_provider_profiles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        protocol TEXT NOT NULL CHECK(protocol IN ('openai_compatible')),
        preset_id TEXT,
        mode TEXT NOT NULL CHECK(mode IN ('localService', 'remote')),
        auth_type TEXT NOT NULL CHECK(auth_type IN ('bearer', 'apiKey', 'none')),
        base_url TEXT NOT NULL,
        model_id TEXT NOT NULL,
        model_version TEXT NOT NULL,
        secret_key_id TEXT NOT NULL,
        distance_metric TEXT NOT NULL CHECK(distance_metric IN ('cosine', 'dotProduct', 'euclidean')),
        dimensions INTEGER,
        max_input_characters INTEGER NOT NULL,
        batch_size INTEGER NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 0,
        is_enabled INTEGER NOT NULL DEFAULT 1,
        remote_content_consent INTEGER NOT NULL DEFAULT 0,
        capability_status TEXT NOT NULL CHECK(capability_status IN ('untested', 'ready', 'unavailable', 'incompatible')),
        capability_error_code TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        CHECK(dimensions IS NULL OR dimensions > 0),
        CHECK(max_input_characters > 0),
        CHECK(batch_size > 0)
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS content_embeddings (
        chunk_id TEXT NOT NULL,
        profile_id TEXT NOT NULL,
        model_id TEXT NOT NULL,
        model_version TEXT NOT NULL,
        dimensions INTEGER NOT NULL,
        distance_metric TEXT NOT NULL CHECK(distance_metric IN ('cosine', 'dotProduct', 'euclidean')),
        content_hash TEXT NOT NULL,
        text_hash TEXT NOT NULL,
        vector_blob BLOB,
        status TEXT NOT NULL CHECK(status IN ('ready', 'failed', 'stale')),
        error_code TEXT,
        generated_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY(chunk_id, profile_id),
        FOREIGN KEY(chunk_id) REFERENCES content_chunks(id) ON DELETE CASCADE,
        FOREIGN KEY(profile_id) REFERENCES embedding_provider_profiles(id) ON DELETE CASCADE,
        CHECK(dimensions > 0),
        CHECK(status != 'ready' OR vector_blob IS NOT NULL)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS content_embeddings_profile_status
      ON content_embeddings(profile_id, status, model_id, model_version)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS semantic_index_states (
        book_id TEXT NOT NULL,
        profile_id TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        model_id TEXT NOT NULL,
        model_version TEXT NOT NULL,
        dimensions INTEGER,
        index_version INTEGER NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('pending', 'indexing', 'ready', 'cancelled', 'failed', 'stale')),
        total_chunks INTEGER NOT NULL DEFAULT 0,
        indexed_chunks INTEGER NOT NULL DEFAULT 0,
        failed_chunks INTEGER NOT NULL DEFAULT 0,
        error_code TEXT,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY(book_id, profile_id),
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE,
        FOREIGN KEY(profile_id) REFERENCES embedding_provider_profiles(id) ON DELETE CASCADE,
        CHECK(dimensions IS NULL OR dimensions > 0),
        CHECK(total_chunks >= 0 AND indexed_chunks >= 0 AND failed_chunks >= 0)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS semantic_index_states_profile_status
      ON semantic_index_states(profile_id, status, updated_at DESC)
    ''');
  }

  Future<void> _createSyncTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS sync_devices (
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        last_seen_at INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS sync_records (
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        revision INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        device_id TEXT NOT NULL,
        operation TEXT NOT NULL CHECK(operation IN ('upsert', 'delete')),
        payload_json TEXT NOT NULL,
        payload_hash TEXT NOT NULL,
        PRIMARY KEY(entity_type, entity_id),
        CHECK(revision > 0)
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS sync_changes (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        revision INTEGER NOT NULL,
        modified_at INTEGER NOT NULL,
        device_id TEXT NOT NULL,
        operation TEXT NOT NULL CHECK(operation IN ('upsert', 'delete')),
        payload_hash TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        UNIQUE(entity_type, entity_id, revision, device_id, payload_hash)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS sync_changes_sequence
      ON sync_changes(sequence)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS sync_tombstones (
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        revision INTEGER NOT NULL,
        deleted_at INTEGER NOT NULL,
        device_id TEXT NOT NULL,
        payload_hash TEXT NOT NULL,
        purge_after INTEGER NOT NULL,
        acknowledged_devices_json TEXT NOT NULL DEFAULT '[]',
        PRIMARY KEY(entity_type, entity_id),
        CHECK(revision > 0)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS sync_tombstones_purge
      ON sync_tombstones(purge_after)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS sync_conflicts (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        field_names_json TEXT NOT NULL,
        local_payload_json TEXT NOT NULL,
        incoming_payload_json TEXT NOT NULL,
        local_revision INTEGER NOT NULL,
        incoming_revision INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        resolved_at INTEGER,
        resolution_payload_json TEXT
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS sync_conflicts_pending
      ON sync_conflicts(resolved_at, created_at)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS sync_state (
        backend_id TEXT NOT NULL,
        remote_id TEXT NOT NULL,
        cursor TEXT,
        last_success_at INTEGER,
        last_summary_json TEXT,
        error_code TEXT,
        credential_ref TEXT,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY(backend_id, remote_id)
      )
    ''');
  }

  Future<void> _createVisualArtifactTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS visual_artifacts (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        kind TEXT NOT NULL CHECK(kind IN ('wordCloud', 'mindMap')),
        scope TEXT NOT NULL CHECK(scope IN ('currentChapter', 'readChapters', 'wholeBook')),
        title TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS visual_artifacts_book_created
      ON visual_artifacts(book_id, created_at DESC)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS word_cloud_cache (
        cache_key TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS word_cloud_cache_book_created
      ON word_cloud_cache(book_id, created_at DESC)
    ''');
  }

  Future<void> _createContentChunkTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS content_chunks (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        chapter_id TEXT NOT NULL,
        chapter_index INTEGER NOT NULL,
        chapter_title TEXT NOT NULL,
        href TEXT NOT NULL,
        locator_start TEXT NOT NULL,
        locator_end TEXT NOT NULL,
        raw_start INTEGER NOT NULL,
        raw_end INTEGER NOT NULL,
        ordinal INTEGER NOT NULL,
        text_content TEXT NOT NULL,
        text_hash TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        parser_version INTEGER NOT NULL,
        index_version INTEGER NOT NULL,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE,
        UNIQUE(book_id, ordinal),
        CHECK(raw_start >= 0 AND raw_end >= raw_start)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS content_chunks_book_chapter
      ON content_chunks(book_id, chapter_index, ordinal)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS content_chunks_book_hash
      ON content_chunks(book_id, content_hash)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS content_index_states (
        book_id TEXT PRIMARY KEY,
        content_hash TEXT NOT NULL,
        parser_version INTEGER NOT NULL,
        index_version INTEGER NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('pending', 'indexing', 'ready', 'failed')),
        progress REAL NOT NULL DEFAULT 0,
        error TEXT,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createTextProjectionTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS text_display_rules (
        id TEXT PRIMARY KEY,
        book_id TEXT,
        name TEXT NOT NULL,
        find_text TEXT NOT NULL,
        replace_text TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        priority INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sync_revision INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE,
        CHECK(length(find_text) BETWEEN 1 AND 200),
        CHECK(length(replace_text) <= 200)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS text_display_rules_scope_priority
      ON text_display_rules(book_id, enabled, priority DESC)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS book_text_projection_settings (
        book_id TEXT PRIMARY KEY,
        settings_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        sync_revision INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createImportedFontsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS imported_fonts (
        id TEXT PRIMARY KEY,
        family TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        file_hash TEXT NOT NULL UNIQUE,
        format TEXT NOT NULL CHECK(format IN ('ttf', 'otf', 'woff', 'woff2')),
        source TEXT NOT NULL,
        license_label TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT 0,
        sync_revision INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS imported_fonts_family
      ON imported_fonts(family COLLATE NOCASE)
    ''');
  }

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
        render_style TEXT NOT NULL DEFAULT 'highlight',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sync_revision INTEGER NOT NULL DEFAULT 1,
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
        updated_at INTEGER NOT NULL DEFAULT 0,
        sync_revision INTEGER NOT NULL DEFAULT 1,
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
        preset_id TEXT,
        auth_type TEXT NOT NULL DEFAULT 'bearer',
        base_url TEXT NOT NULL,
        model_id TEXT NOT NULL,
        secret_key_id TEXT NOT NULL,
        temperature REAL NOT NULL DEFAULT 0.3,
        max_output_tokens INTEGER NOT NULL DEFAULT 2048,
        is_active INTEGER NOT NULL DEFAULT 0,
        is_enabled INTEGER NOT NULL DEFAULT 1,
        enable_tools INTEGER NOT NULL DEFAULT 0,
        enable_reasoning INTEGER NOT NULL DEFAULT 1,
        capabilities_json TEXT NOT NULL DEFAULT '{}',
        custom_headers_secret_id TEXT,
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
        sync_revision INTEGER NOT NULL DEFAULT 1,
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
        input_tokens INTEGER,
        output_tokens INTEGER,
        reasoning_tokens INTEGER,
        cached_tokens INTEGER,
        stop_reason TEXT,
        created_at INTEGER NOT NULL,
        completed_at INTEGER,
        updated_at INTEGER NOT NULL DEFAULT 0,
        sync_revision INTEGER NOT NULL DEFAULT 1,
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

  Future<void> _createAiAgentTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS chat_message_parts (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        ordinal INTEGER NOT NULL,
        type TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('pending', 'running', 'completed', 'error')),
        text_content TEXT,
        payload_json TEXT,
        provider_item_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(message_id) REFERENCES chat_messages(id) ON DELETE CASCADE,
        UNIQUE(message_id, ordinal)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS chat_message_parts_message_ordinal
      ON chat_message_parts(message_id, ordinal)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS ai_runs (
        id TEXT PRIMARY KEY,
        thread_id TEXT NOT NULL,
        user_message_id TEXT NOT NULL,
        assistant_message_id TEXT NOT NULL,
        provider_profile_id TEXT NOT NULL,
        model_id TEXT NOT NULL,
        status TEXT NOT NULL,
        stop_reason TEXT,
        error_code TEXT,
        input_tokens INTEGER,
        output_tokens INTEGER,
        reasoning_tokens INTEGER,
        cached_tokens INTEGER,
        started_at INTEGER NOT NULL,
        completed_at INTEGER,
        FOREIGN KEY(thread_id) REFERENCES chat_threads(id) ON DELETE CASCADE,
        FOREIGN KEY(user_message_id) REFERENCES chat_messages(id) ON DELETE CASCADE,
        FOREIGN KEY(assistant_message_id) REFERENCES chat_messages(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS ai_runs_thread_started
      ON ai_runs(thread_id, started_at DESC)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS ai_tool_executions (
        id TEXT PRIMARY KEY,
        run_id TEXT NOT NULL,
        part_id TEXT NOT NULL,
        call_id TEXT NOT NULL,
        tool_name TEXT NOT NULL,
        tool_kind TEXT NOT NULL,
        arguments_json TEXT NOT NULL,
        result_text TEXT,
        status TEXT NOT NULL,
        error_message TEXT,
        duration_ms INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(run_id) REFERENCES ai_runs(id) ON DELETE CASCADE,
        FOREIGN KEY(part_id) REFERENCES chat_message_parts(id) ON DELETE CASCADE,
        UNIQUE(run_id, call_id)
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS ai_skills (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL,
        icon_key TEXT NOT NULL,
        is_enabled INTEGER NOT NULL,
        is_built_in INTEGER NOT NULL,
        version INTEGER NOT NULL,
        prompt_template TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _createReadingSessionsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS reading_sessions (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        session_group_id TEXT NOT NULL,
        format TEXT NOT NULL CHECK(format IN ('epub', 'pdf', 'text')),
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

  Future<void> _createTextColoringTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS book_text_coloring_overrides (
        book_id TEXT PRIMARY KEY,
        enabled INTEGER,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE,
        CHECK(enabled IS NULL OR enabled IN (0, 1))
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS text_color_terms (
        id TEXT PRIMARY KEY,
        book_id TEXT,
        term TEXT NOT NULL,
        normalized_term TEXT NOT NULL,
        color_token TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS text_color_terms_global_normalized
      ON text_color_terms(normalized_term)
      WHERE book_id IS NULL
    ''');
    await database.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS text_color_terms_book_normalized
      ON text_color_terms(book_id, normalized_term)
      WHERE book_id IS NOT NULL
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS text_color_terms_book_updated
      ON text_color_terms(book_id, updated_at DESC)
    ''');
  }

  Future<void> _createPomodoroSessionsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS pomodoro_sessions (
        id TEXT PRIMARY KEY,
        book_id TEXT,
        phase TEXT NOT NULL CHECK(phase IN ('focus', 'shortBreak', 'longBreak')),
        planned_millis INTEGER NOT NULL,
        elapsed_millis INTEGER NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('completed', 'cancelled', 'skipped')),
        started_at INTEGER NOT NULL,
        ended_at INTEGER NOT NULL,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE SET NULL,
        CHECK(planned_millis >= 0),
        CHECK(elapsed_millis >= 0 AND elapsed_millis <= planned_millis)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS pomodoro_sessions_started
      ON pomodoro_sessions(started_at DESC)
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS pomodoro_sessions_book_started
      ON pomodoro_sessions(book_id, started_at DESC)
    ''');
  }

  Future<void> _createTextContentTables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS text_content_profiles (
        book_id TEXT PRIMARY KEY,
        encoding TEXT NOT NULL,
        encoding_confidence REAL,
        parser_version INTEGER NOT NULL,
        content_hash TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS text_chapters (
        id TEXT PRIMARY KEY,
        book_id TEXT NOT NULL,
        ordinal INTEGER NOT NULL,
        title TEXT NOT NULL,
        raw_start INTEGER NOT NULL,
        raw_end INTEGER NOT NULL,
        source_rule_id TEXT,
        content_hash TEXT NOT NULL,
        FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE,
        UNIQUE(book_id, ordinal),
        CHECK(raw_start >= 0 AND raw_end >= raw_start)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS text_chapters_book_range
      ON text_chapters(book_id, raw_start, raw_end)
    ''');
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

class DatabaseSnapshotInfo {
  const DatabaseSnapshotInfo({
    required this.schemaVersion,
    required this.bookIds,
    required this.fontIds,
  });

  final int schemaVersion;
  final Set<String> bookIds;
  final Set<String> fontIds;
}

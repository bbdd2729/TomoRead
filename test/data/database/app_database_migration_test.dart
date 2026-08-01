import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tomoread/data/database/app_database.dart';

void main() {
  test('migrates v10 chat messages to structured parts', () async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp(
      'tomoread-migration-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final databasePath = '${directory.path}${Platform.pathSeparator}app.db';
    final oldDatabase = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 10,
        onCreate: (database, _) async {
          await database.execute('''
            CREATE TABLE ai_provider_profiles (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              protocol TEXT NOT NULL,
              base_url TEXT NOT NULL,
              model_id TEXT NOT NULL,
              secret_key_id TEXT NOT NULL,
              temperature REAL NOT NULL,
              max_output_tokens INTEGER NOT NULL,
              is_active INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE chat_threads (
              id TEXT PRIMARY KEY,
              scope TEXT NOT NULL,
              book_id TEXT,
              title TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await database.execute('''
            CREATE TABLE chat_messages (
              id TEXT PRIMARY KEY,
              thread_id TEXT NOT NULL,
              role TEXT NOT NULL,
              content TEXT NOT NULL,
              status TEXT NOT NULL,
              model_id TEXT,
              error_code TEXT,
              created_at INTEGER NOT NULL,
              completed_at INTEGER
            )
          ''');
          await database.insert('chat_threads', {
            'id': 'thread-a',
            'scope': 'general',
            'title': 'Old thread',
            'created_at': 1,
            'updated_at': 1,
          });
          await database.insert('chat_messages', {
            'id': 'message-a',
            'thread_id': 'thread-a',
            'role': 'assistant',
            'content': 'Legacy answer',
            'status': 'complete',
            'created_at': 1,
            'completed_at': 2,
          });
        },
      ),
    );
    await oldDatabase.close();

    final appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      pathProvider: () async => databasePath,
    );
    addTearDown(appDatabase.close);
    final database = await appDatabase.database;

    expect(await database.getVersion(), 11);
    final parts = await database.query('chat_message_parts');
    expect(parts.single['type'], 'text');
    expect(parts.single['text_content'], 'Legacy answer');
    final providerColumns = await database.rawQuery(
      'PRAGMA table_info(ai_provider_profiles)',
    );
    expect(
      providerColumns.map((column) => column['name']),
      containsAll(['enable_tools', 'enable_reasoning']),
    );
  });
}

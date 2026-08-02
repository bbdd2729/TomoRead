import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/models/visual_artifact.dart';
import '../database/app_database.dart';

class VisualArtifactRepository {
  VisualArtifactRepository(this._database);

  final AppDatabase _database;

  Future<VisualArtifact> save({
    required String bookId,
    required VisualArtifactKind kind,
    required VisualArtifactScope scope,
    required String title,
    required String contentHash,
    required Map<String, Object?> payload,
  }) async {
    final now = DateTime.now();
    final id = sha256
        .convert(
          utf8.encode(
            '$bookId:${kind.name}:$contentHash:${now.microsecondsSinceEpoch}',
          ),
        )
        .toString()
        .substring(0, 32);
    final artifact = VisualArtifact(
      id: id,
      bookId: bookId,
      kind: kind,
      scope: scope,
      title: title.trim(),
      contentHash: contentHash,
      payloadJson: jsonEncode(payload),
      createdAt: now,
    );
    final database = await _database.database;
    await database.insert('visual_artifacts', _toRow(artifact));
    return artifact;
  }

  Future<List<VisualArtifact>> listForBook(String bookId) async {
    final database = await _database.database;
    final rows = await database.query(
      'visual_artifacts',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'created_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<VisualArtifact?> findById(String id) async {
    final database = await _database.database;
    final rows = await database.query(
      'visual_artifacts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  Future<void> delete(String id) async {
    final database = await _database.database;
    await database.delete('visual_artifacts', where: 'id = ?', whereArgs: [id]);
  }

  Future<WordCloudPayload?> loadWordCloudCache(String cacheKey) async {
    final database = await _database.database;
    final rows = await database.query(
      'word_cloud_cache',
      columns: ['payload_json'],
      where: 'cache_key = ?',
      whereArgs: [cacheKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      return WordCloudPayload.fromJson(
        jsonDecode(rows.single['payload_json']! as String)
            as Map<String, Object?>,
      );
    } on Object {
      return null;
    }
  }

  Future<void> saveWordCloudCache({
    required String cacheKey,
    required String bookId,
    required WordCloudPayload payload,
  }) async {
    final database = await _database.database;
    await database.insert('word_cloud_cache', {
      'cache_key': cacheKey,
      'book_id': bookId,
      'payload_json': jsonEncode(payload.toJson()),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Map<String, Object?> _toRow(VisualArtifact artifact) => {
    'id': artifact.id,
    'book_id': artifact.bookId,
    'kind': artifact.kind.name,
    'scope': artifact.scope.name,
    'title': artifact.title,
    'content_hash': artifact.contentHash,
    'payload_json': artifact.payloadJson,
    'created_at': artifact.createdAt.millisecondsSinceEpoch,
  };

  VisualArtifact _fromRow(Map<String, Object?> row) => VisualArtifact(
    id: row['id']! as String,
    bookId: row['book_id']! as String,
    kind: VisualArtifactKind.values.byName(row['kind']! as String),
    scope: VisualArtifactScope.values.byName(row['scope']! as String),
    title: row['title']! as String,
    contentHash: row['content_hash']! as String,
    payloadJson: row['payload_json']! as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
  );
}

import 'dart:typed_data';

import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/models/content_chunk.dart';
import '../../domain/models/embedding_models.dart';
import '../database/app_database.dart';

class SemanticEmbeddingCandidate {
  const SemanticEmbeddingCandidate({
    required this.chunk,
    required this.vector,
  });

  final ContentChunk chunk;
  final List<double> vector;
}

class ContentEmbeddingRepository {
  ContentEmbeddingRepository(this._database);

  final AppDatabase _database;

  Future<SemanticIndexState?> loadState({
    required String bookId,
    required String profileId,
  }) async {
    final database = await _database.database;
    final rows = await database.query(
      'semantic_index_states',
      where: 'book_id = ? AND profile_id = ?',
      whereArgs: [bookId, profileId],
      limit: 1,
    );
    return rows.isEmpty ? null : _stateFromRow(rows.single);
  }

  Future<List<SemanticIndexState>> listStatesForProfile(
    String profileId,
  ) async {
    final database = await _database.database;
    final rows = await database.query(
      'semantic_index_states',
      where: 'profile_id = ?',
      whereArgs: [profileId],
      orderBy: 'updated_at DESC',
    );
    return rows.map(_stateFromRow).toList();
  }

  Future<void> beginIndex({
    required String bookId,
    required EmbeddingProviderProfile profile,
    required String contentHash,
    required int indexVersion,
    required int totalChunks,
    required int indexedChunks,
  }) => saveState(
    SemanticIndexState(
      bookId: bookId,
      profileId: profile.id,
      contentHash: contentHash,
      modelId: profile.modelId,
      modelVersion: profile.modelVersion,
      dimensions: profile.dimensions,
      indexVersion: indexVersion,
      status: SemanticIndexStatus.indexing,
      totalChunks: totalChunks,
      indexedChunks: indexedChunks,
      failedChunks: 0,
      updatedAt: DateTime.now(),
    ),
  );

  Future<void> saveState(SemanticIndexState state) async {
    final database = await _database.database;
    await database.insert(
      'semantic_index_states',
      _stateToRow(state),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Set<String>> readyChunkIds({
    required String bookId,
    required EmbeddingProviderProfile profile,
    required String contentHash,
  }) async {
    final database = await _database.database;
    final rows = await database.rawQuery('''
      SELECT e.chunk_id
      FROM content_embeddings e
      INNER JOIN content_chunks c ON c.id = e.chunk_id
      WHERE c.book_id = ?
        AND e.profile_id = ?
        AND e.model_id = ?
        AND e.model_version = ?
        AND e.content_hash = ?
        AND e.text_hash = c.text_hash
        AND e.status = 'ready'
        ${profile.dimensions == null ? '' : 'AND e.dimensions = ?'}
    ''', [
      bookId,
      profile.id,
      profile.modelId,
      profile.modelVersion,
      contentHash,
      if (profile.dimensions != null) profile.dimensions,
    ]);
    return rows.map((row) => row['chunk_id']! as String).toSet();
  }

  Future<void> saveBatch({
    required EmbeddingProviderProfile profile,
    required List<ContentChunk> chunks,
    required List<List<double>> vectors,
  }) async {
    if (chunks.length != vectors.length) {
      throw const FormatException('Embedding response count does not match.');
    }
    final database = await _database.database;
    final now = DateTime.now();
    await database.transaction((transaction) async {
      for (var index = 0; index < chunks.length; index++) {
        final chunk = chunks[index];
        final vector = vectors[index];
        if (vector.isEmpty ||
            (profile.dimensions != null &&
                vector.length != profile.dimensions)) {
          throw const FormatException('Embedding dimensions do not match.');
        }
        await transaction.insert(
          'content_embeddings',
          {
            'chunk_id': chunk.id,
            'profile_id': profile.id,
            'model_id': profile.modelId,
            'model_version': profile.modelVersion,
            'dimensions': vector.length,
            'distance_metric': profile.distanceMetric.name,
            'content_hash': chunk.contentHash,
            'text_hash': chunk.textHash,
            'vector_blob': _encodeVector(vector),
            'status': ContentEmbeddingStatus.ready.name,
            'error_code': null,
            'generated_at': now.millisecondsSinceEpoch,
            'updated_at': now.millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> invalidateMismatched({
    required String bookId,
    required EmbeddingProviderProfile profile,
    required String contentHash,
  }) async {
    final database = await _database.database;
    final conditions = <String>[
      'profile_id = ?',
      'chunk_id IN (SELECT id FROM content_chunks WHERE book_id = ?)',
      '(model_id != ? OR model_version != ? OR content_hash != ?',
    ];
    final arguments = <Object?>[
      profile.id,
      bookId,
      profile.modelId,
      profile.modelVersion,
      contentHash,
    ];
    if (profile.dimensions != null) {
      conditions.last = '${conditions.last} OR dimensions != ?)';
      arguments.add(profile.dimensions);
    } else {
      conditions.last = '${conditions.last})';
    }
    await database.update(
      'content_embeddings',
      {
        'status': ContentEmbeddingStatus.stale.name,
        'error_code': 'index_identity_changed',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: conditions.join(' AND '),
      whereArgs: arguments,
    );
  }

  Future<List<SemanticEmbeddingCandidate>> listCandidates({
    required String bookId,
    required EmbeddingProviderProfile profile,
    required String contentHash,
    int? maxChapterIndex,
    int limit = 10000,
  }) async {
    if (profile.dimensions == null) return const [];
    final database = await _database.database;
    final rows = await database.rawQuery('''
      SELECT c.*, e.vector_blob, e.dimensions AS embedding_dimensions
      FROM content_embeddings e
      INNER JOIN content_chunks c ON c.id = e.chunk_id
      WHERE c.book_id = ?
        AND e.profile_id = ?
        AND e.model_id = ?
        AND e.model_version = ?
        AND e.dimensions = ?
        AND e.content_hash = ?
        AND e.text_hash = c.text_hash
        AND e.status = 'ready'
        ${maxChapterIndex == null ? '' : 'AND c.chapter_index <= ?'}
      ORDER BY c.ordinal ASC
      LIMIT ?
    ''', [
      bookId,
      profile.id,
      profile.modelId,
      profile.modelVersion,
      profile.dimensions,
      contentHash,
      if (maxChapterIndex != null) maxChapterIndex,
      limit.clamp(1, 10000),
    ]);
    return rows.map((row) {
      final dimensions = row['embedding_dimensions']! as int;
      return SemanticEmbeddingCandidate(
        chunk: _chunkFromRow(row),
        vector: _decodeVector(row['vector_blob']!, dimensions),
      );
    }).toList();
  }

  Future<void> deleteForBook({
    required String bookId,
    required String profileId,
  }) async {
    final database = await _database.database;
    await database.transaction((transaction) async {
      await transaction.delete(
        'content_embeddings',
        where:
            'profile_id = ? AND chunk_id IN '
            '(SELECT id FROM content_chunks WHERE book_id = ?)',
        whereArgs: [profileId, bookId],
      );
      await transaction.delete(
        'semantic_index_states',
        where: 'book_id = ? AND profile_id = ?',
        whereArgs: [bookId, profileId],
      );
    });
  }

  Map<String, Object?> _stateToRow(SemanticIndexState state) => {
    'book_id': state.bookId,
    'profile_id': state.profileId,
    'content_hash': state.contentHash,
    'model_id': state.modelId,
    'model_version': state.modelVersion,
    'dimensions': state.dimensions,
    'index_version': state.indexVersion,
    'status': state.status.name,
    'total_chunks': state.totalChunks,
    'indexed_chunks': state.indexedChunks,
    'failed_chunks': state.failedChunks,
    'error_code': state.errorCode,
    'updated_at': state.updatedAt.millisecondsSinceEpoch,
  };

  SemanticIndexState _stateFromRow(Map<String, Object?> row) =>
      SemanticIndexState(
        bookId: row['book_id']! as String,
        profileId: row['profile_id']! as String,
        contentHash: row['content_hash']! as String,
        modelId: row['model_id']! as String,
        modelVersion: row['model_version']! as String,
        dimensions: row['dimensions'] as int?,
        indexVersion: row['index_version']! as int,
        status: SemanticIndexStatus.values.firstWhere(
          (value) => value.name == row['status'],
          orElse: () => SemanticIndexStatus.failed,
        ),
        totalChunks: row['total_chunks']! as int,
        indexedChunks: row['indexed_chunks']! as int,
        failedChunks: row['failed_chunks']! as int,
        errorCode: row['error_code'] as String?,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          row['updated_at']! as int,
        ),
      );

  Uint8List _encodeVector(List<double> vector) {
    final bytes = ByteData(vector.length * Float32List.bytesPerElement);
    for (var index = 0; index < vector.length; index++) {
      bytes.setFloat32(
        index * Float32List.bytesPerElement,
        vector[index],
        Endian.little,
      );
    }
    return bytes.buffer.asUint8List();
  }

  List<double> _decodeVector(Object source, int dimensions) {
    final bytes = source is Uint8List
        ? source
        : Uint8List.fromList((source as List<Object?>).cast<int>());
    if (bytes.length != dimensions * Float32List.bytesPerElement) {
      throw const FormatException('Stored embedding dimensions do not match.');
    }
    final data = ByteData.sublistView(bytes);
    return List<double>.generate(
      dimensions,
      (index) => data.getFloat32(
        index * Float32List.bytesPerElement,
        Endian.little,
      ),
      growable: false,
    );
  }

  ContentChunk _chunkFromRow(Map<String, Object?> row) => ContentChunk(
    id: row['id']! as String,
    bookId: row['book_id']! as String,
    chapterId: row['chapter_id']! as String,
    chapterIndex: row['chapter_index']! as int,
    chapterTitle: row['chapter_title']! as String,
    href: row['href']! as String,
    locatorStart: row['locator_start']! as String,
    locatorEnd: row['locator_end']! as String,
    rawStart: row['raw_start']! as int,
    rawEnd: row['raw_end']! as int,
    ordinal: row['ordinal']! as int,
    text: row['text_content']! as String,
    textHash: row['text_hash']! as String,
    contentHash: row['content_hash']! as String,
    parserVersion: row['parser_version']! as int,
    indexVersion: row['index_version']! as int,
  );
}

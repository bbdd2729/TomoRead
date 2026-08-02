import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../domain/models/book_import.dart';
import '../../domain/models/epub_manifest.dart';
import '../../domain/models/library_book.dart';
import '../../domain/models/text_content_profile.dart';
import '../repositories/book_repository.dart';
import '../repositories/content_chunk_repository.dart';
import '../repositories/text_content_repository.dart';
import 'book_import_scan_service.dart';
import 'chapter_parser_service.dart';
import 'content_chunk_service.dart';
import 'epub_content_service.dart';
import 'epub_parser.dart';
import 'import_cancellation_token.dart';
import 'text_decoder_service.dart';

enum BookImportStatus { imported, duplicate, needsEncoding, failed }

class BookImportResult {
  const BookImportResult._({
    required this.sourcePath,
    required this.status,
    this.book,
    this.error,
    this.textPreview,
    this.detectedEncoding,
    this.encodingCandidates = const [],
  });

  factory BookImportResult.imported(String sourcePath, LibraryBook book) =>
      BookImportResult._(
        sourcePath: sourcePath,
        status: BookImportStatus.imported,
        book: book,
      );

  factory BookImportResult.duplicate(String sourcePath, LibraryBook book) =>
      BookImportResult._(
        sourcePath: sourcePath,
        status: BookImportStatus.duplicate,
        book: book,
      );

  factory BookImportResult.failed(String sourcePath, String error) =>
      BookImportResult._(
        sourcePath: sourcePath,
        status: BookImportStatus.failed,
        error: error,
      );

  factory BookImportResult.needsEncoding(
    String sourcePath,
    TextDecodeResult result,
  ) => BookImportResult._(
    sourcePath: sourcePath,
    status: BookImportStatus.needsEncoding,
    textPreview: result.preview,
    detectedEncoding: result.encoding,
    encodingCandidates: result.candidates,
  );

  final String sourcePath;
  final BookImportStatus status;
  final LibraryBook? book;
  final String? error;
  final String? textPreview;
  final String? detectedEncoding;
  final List<String> encodingCandidates;
}

class BookImportService {
  BookImportService({
    required this.repository,
    EpubParser? epubParser,
    TextDecoderService? textDecoder,
    ChapterParserService? chapterParser,
    TextContentRepository? textContentRepository,
    ContentChunkService? contentChunkService,
    BookImportScanService? scanService,
    this.libraryRootProvider,
  }) : parser = epubParser ?? const EpubParser(),
       textDecoder = textDecoder ?? const TextDecoderService(),
       chapterParser = chapterParser ?? const ChapterParserService(),
       textContentRepository =
           textContentRepository ?? TextContentRepository(repository.database),
       contentChunkService =
           contentChunkService ??
           ContentChunkService(
             repository: ContentChunkRepository(repository.database),
             epubContent: const EpubContentService(),
           ),
       scanService = scanService ?? const BookImportScanService();

  final BookRepository repository;
  final EpubParser parser;
  final TextDecoderService textDecoder;
  final ChapterParserService chapterParser;
  final TextContentRepository textContentRepository;
  final ContentChunkService contentChunkService;
  final BookImportScanService scanService;
  final Future<Directory> Function()? libraryRootProvider;

  Future<List<ImportSource>> pickImportSources() async {
    final selection = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['epub', 'pdf', 'txt', 'md', 'markdown'],
    );
    if (selection == null) return const [];
    return selection.files
        .map((file) => file.path)
        .whereType<String>()
        .map(
          (value) => ImportSource(
            kind: ImportSourceKind.filePicker,
            location: value,
          ),
        )
        .toList(growable: false);
  }

  Future<ImportSource?> pickImportDirectorySource() async {
    final selected = await FilePicker.getDirectoryPath();
    if (selected == null) return null;
    return ImportSource(
      kind: ImportSourceKind.directoryPicker,
      location: selected,
    );
  }

  Future<ImportScanPreview> previewSources(
    Iterable<ImportSource> sources, {
    ImportScanLimits limits = const ImportScanLimits(),
    ImportCancellationToken? cancellationToken,
    void Function(int processed, int total)? onHashProgress,
  }) async {
    final directories = await _libraryDirectories();
    final scanned = await scanService.scan(
      sources,
      limits: limits,
      cancellationToken: cancellationToken,
      excludedRoots: [directories.library.path],
    );
    if (scanned.cancelled) return scanned;

    final items = List<ImportScanItem>.from(scanned.items);
    final hashes = <String, String>{};
    final supportedIndexes = <int>[
      for (var index = 0; index < items.length; index++)
        if (items[index].disposition == ImportScanDisposition.supported) index,
    ];
    var processed = 0;
    for (final index in supportedIndexes) {
      if (cancellationToken?.isCancelled == true) {
        return scanned.copyWith(items: List.unmodifiable(items), cancelled: true);
      }
      final item = items[index];
      final request = item.request!;
      try {
        final hash = await _hashFile(
          File(request.sourcePath),
          cancellationToken: cancellationToken,
        );
        final firstPath = hashes[hash];
        if (firstPath != null) {
          items[index] = item.copyWith(
            disposition: ImportScanDisposition.duplicate,
            reason: '与本次扫描中的 ${path.basename(firstPath)} 内容重复',
          );
        } else {
          hashes[hash] = request.sourcePath;
          final duplicate = await repository.findByHash(hash);
          if (duplicate != null) {
            items[index] = item.copyWith(
              disposition: ImportScanDisposition.duplicate,
              reason: '书库中已存在相同内容',
              duplicateBookId: duplicate.id,
            );
          }
        }
      } on ImportCancelledException {
        return scanned.copyWith(items: List.unmodifiable(items), cancelled: true);
      } on FileSystemException catch (error) {
        items[index] = item.copyWith(
          disposition: ImportScanDisposition.failed,
          reason: error.message,
        );
      }
      processed++;
      onHashProgress?.call(processed, supportedIndexes.length);
    }
    return scanned.copyWith(items: List.unmodifiable(items));
  }

  Future<List<BookImportResult>> importPreview(
    ImportScanPreview preview, {
    ImportCancellationToken? cancellationToken,
    void Function(int completed, int total)? onProgress,
  }) async {
    final requests = preview.requests;
    final results = <BookImportResult>[];
    for (final request in requests) {
      if (cancellationToken?.isCancelled == true) break;
      results.add(await importBookFile(request.sourcePath));
      onProgress?.call(results.length, requests.length);
    }
    return List.unmodifiable(results);
  }

  Future<List<BookImportResult>> pickAndImportBooks() async {
    final sources = await pickImportSources();
    if (sources.isEmpty) return const [];
    return Future.wait(
      sources.map((source) => importBookFile(source.location)),
    );
  }

  Future<List<BookImportResult>> pickAndImportEpubs() => pickAndImportBooks();

  Future<BookImportResult> importBookFile(String sourcePath) {
    return switch (path.extension(sourcePath).toLowerCase()) {
      '.epub' => importEpubFile(sourcePath),
      '.pdf' => importPdfFile(sourcePath),
      '.txt' || '.md' || '.markdown' => importTextFile(sourcePath),
      _ => Future.value(
        BookImportResult.failed(sourcePath, '仅支持导入 EPUB、PDF、TXT 或 Markdown 文件'),
      ),
    };
  }

  Future<BookImportResult> importEpubFile(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      return BookImportResult.failed(sourcePath, '找不到选择的文件');
    }
    if (path.extension(sourcePath).toLowerCase() != '.epub') {
      return BookImportResult.failed(sourcePath, '仅支持导入 EPUB 文件');
    }

    final directories = await _libraryDirectories();
    final temporaryPath = path.join(
      directories.imports.path,
      '${DateTime.now().microsecondsSinceEpoch}.epub',
    );
    final temporaryFile = File(temporaryPath);
    try {
      final hash = await _copyAndHash(source, temporaryFile);
      final duplicate = await repository.findByHash(hash);
      if (duplicate != null) {
        await temporaryFile.delete();
        return BookImportResult.duplicate(sourcePath, duplicate);
      }

      final targetFile = File(path.join(directories.books.path, '$hash.epub'));
      if (await targetFile.exists()) {
        await temporaryFile.delete();
      } else {
        await temporaryFile.rename(targetFile.path);
      }

      final parsed = await parser.parseFile(targetFile.path);
      String? coverPath;
      if (parsed.coverBytes != null && parsed.coverBytes!.isNotEmpty) {
        final extension = _safeCoverExtension(parsed.coverExtension);
        final coverFile = File(
          path.join(directories.covers.path, '$hash$extension'),
        );
        await coverFile.writeAsBytes(parsed.coverBytes!, flush: true);
        coverPath = coverFile.path;
      }
      final book = LibraryBook(
        id: hash,
        fileHash: hash,
        title: parsed.title,
        author: parsed.author,
        filePath: targetFile.path,
        coverPath: coverPath,
        description: parsed.description,
        progress: 0,
        importedAt: DateTime.now(),
        format: 'epub',
        chapterCount: parsed.manifest.chapterCount,
        direction: parsed.manifest.direction,
      );
      await repository.saveImportedBook(
        ImportedBook(book: book, manifest: parsed.manifest),
      );
      try {
        await contentChunkService.rebuildEpub(
          book: book,
          manifest: parsed.manifest,
        );
      } on Object {
        // The independently rebuildable index records its own failure state.
      }
      return BookImportResult.imported(sourcePath, book);
    } on EpubParseException catch (error) {
      if (await temporaryFile.exists()) await temporaryFile.delete();
      return BookImportResult.failed(sourcePath, error.message);
    } catch (error) {
      if (await temporaryFile.exists()) await temporaryFile.delete();
      return BookImportResult.failed(sourcePath, '导入失败：$error');
    }
  }

  Future<BookImportResult> importPdfFile(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      return BookImportResult.failed(sourcePath, '找不到选择的文件');
    }
    if (path.extension(sourcePath).toLowerCase() != '.pdf') {
      return BookImportResult.failed(sourcePath, '仅支持导入 PDF 文件');
    }

    final directories = await _libraryDirectories();
    final temporaryFile = File(
      path.join(
        directories.imports.path,
        '${DateTime.now().microsecondsSinceEpoch}.pdf',
      ),
    );
    try {
      final hash = await _copyAndHash(source, temporaryFile);
      final duplicate = await repository.findByHash(hash);
      if (duplicate != null) {
        await temporaryFile.delete();
        return BookImportResult.duplicate(sourcePath, duplicate);
      }
      final targetFile = File(path.join(directories.books.path, '$hash.pdf'));
      if (await targetFile.exists()) {
        await temporaryFile.delete();
      } else {
        await temporaryFile.rename(targetFile.path);
      }
      final document = await PdfDocument.openFile(targetFile.path);
      final pageCount = document.pages.length;
      await document.dispose();
      final book = LibraryBook(
        id: hash,
        fileHash: hash,
        title: path.basenameWithoutExtension(sourcePath),
        author: '',
        filePath: targetFile.path,
        progress: 0,
        importedAt: DateTime.now(),
        format: 'pdf',
        chapterCount: pageCount,
        direction: ReadingDirection.ltr,
      );
      await repository.saveImportedPdfBook(book);
      return BookImportResult.imported(sourcePath, book);
    } catch (error) {
      if (await temporaryFile.exists()) await temporaryFile.delete();
      return BookImportResult.failed(sourcePath, 'PDF 导入失败：$error');
    }
  }

  Future<BookImportResult> importTextFile(
    String sourcePath, {
    String? encodingOverride,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      return BookImportResult.failed(sourcePath, '找不到选择的文件');
    }
    final extension = path.extension(sourcePath).toLowerCase();
    if (!const {'.txt', '.md', '.markdown'}.contains(extension)) {
      return BookImportResult.failed(sourcePath, '仅支持导入 TXT 或 Markdown 文件');
    }
    final directories = await _libraryDirectories();
    final temporaryFile = File(
      path.join(
        directories.imports.path,
        '${DateTime.now().microsecondsSinceEpoch}$extension',
      ),
    );
    File? targetFile;
    LibraryBook? savedBook;
    try {
      final hash = await _copyAndHash(source, temporaryFile);
      final duplicate = await repository.findByHash(hash);
      if (duplicate != null) {
        await temporaryFile.delete();
        return BookImportResult.duplicate(sourcePath, duplicate);
      }
      final decoded = await textDecoder.decodeFile(
        temporaryFile.path,
        encodingOverride: encodingOverride,
      );
      if (decoded.requiresUserConfirmation && encodingOverride == null) {
        await temporaryFile.delete();
        return BookImportResult.needsEncoding(sourcePath, decoded);
      }
      final format = extension == '.txt' ? 'txt' : 'markdown';
      final targetExtension = format == 'txt' ? '.txt' : '.md';
      final managedFile = File(
        path.join(directories.books.path, '$hash$targetExtension'),
      );
      targetFile = managedFile;
      if (await managedFile.exists()) {
        await temporaryFile.delete();
      } else {
        await temporaryFile.rename(managedFile.path);
      }
      final parsed = await chapterParser.parse(
        bookId: hash,
        text: decoded.text,
        contentHash: decoded.contentHash,
        markdown: format == 'markdown',
      );
      final book = LibraryBook(
        id: hash,
        fileHash: hash,
        title: path.basenameWithoutExtension(sourcePath),
        author: '',
        filePath: managedFile.path,
        progress: 0,
        importedAt: DateTime.now(),
        format: format,
        chapterCount: parsed.chapters.length,
        direction: ReadingDirection.ltr,
      );
      await repository.saveImportedStandaloneBook(book);
      savedBook = book;
      await textContentRepository.saveProfileAndChapters(
        TextContentProfile(
          bookId: book.id,
          encoding: decoded.encoding,
          encodingConfidence: decoded.confidence,
          parserVersion: ChapterParserService.parserVersion,
          contentHash: decoded.contentHash,
          updatedAt: DateTime.now(),
        ),
        parsed.chapters,
      );
      try {
        await contentChunkService.rebuildText(
          bookId: book.id,
          rawText: decoded.text,
          contentHash: decoded.contentHash,
          chapters: parsed.chapters,
        );
      } on Object {
        // Reading remains available while the failed index can be rebuilt.
      }
      return BookImportResult.imported(sourcePath, book);
    } on TextDecodeException catch (error) {
      if (await temporaryFile.exists()) await temporaryFile.delete();
      return BookImportResult.failed(sourcePath, error.message);
    } on Object catch (error) {
      if (await temporaryFile.exists()) await temporaryFile.delete();
      if (savedBook != null) await repository.deleteBook(savedBook.id);
      if (targetFile != null && await targetFile.exists()) {
        await targetFile.delete();
      }
      return BookImportResult.failed(sourcePath, '文本导入失败：$error');
    }
  }

  Future<String> _copyAndHash(File source, File destination) async {
    final output = destination.openWrite();
    final digestSink = _DigestSink();
    final hashSink = sha256.startChunkedConversion(digestSink);
    try {
      await for (final chunk in source.openRead()) {
        hashSink.add(chunk);
        output.add(chunk);
      }
      hashSink.close();
      await output.close();
      return digestSink.digest.toString();
    } catch (_) {
      await output.close();
      rethrow;
    }
  }

  Future<String> _hashFile(
    File source, {
    ImportCancellationToken? cancellationToken,
  }) async {
    final digestSink = _DigestSink();
    final hashSink = sha256.startChunkedConversion(digestSink);
    await for (final chunk in source.openRead()) {
      if (cancellationToken?.isCancelled == true) {
        hashSink.close();
        throw const ImportCancelledException();
      }
      hashSink.add(chunk);
    }
    hashSink.close();
    return digestSink.digest.toString();
  }

  Future<_LibraryDirectories> _libraryDirectories() async {
    final root = libraryRootProvider == null
        ? await getApplicationSupportDirectory()
        : await libraryRootProvider!();
    final library = Directory(path.join(root.path, 'library'));
    final books = Directory(path.join(library.path, 'books'));
    final covers = Directory(path.join(library.path, 'covers'));
    final imports = Directory(path.join(library.path, 'imports'));
    for (final directory in [books, covers, imports]) {
      if (!await directory.exists()) await directory.create(recursive: true);
    }
    return _LibraryDirectories(
      library: library,
      books: books,
      covers: covers,
      imports: imports,
    );
  }

  String _safeCoverExtension(String? source) {
    const supported = {'.jpg', '.jpeg', '.png', '.webp'};
    final extension = source?.toLowerCase();
    return extension != null && supported.contains(extension)
        ? extension
        : '.jpg';
  }
}

class _LibraryDirectories {
  const _LibraryDirectories({
    required this.library,
    required this.books,
    required this.covers,
    required this.imports,
  });

  final Directory library;
  final Directory books;
  final Directory covers;
  final Directory imports;
}

class _DigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get digest => _digest!;

  @override
  void add(Digest data) => _digest = data;

  @override
  void close() {}
}

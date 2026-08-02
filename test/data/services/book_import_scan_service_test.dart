import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:tomoread/data/services/book_import_scan_service.dart';
import 'package:tomoread/data/services/import_cancellation_token.dart';
import 'package:tomoread/domain/models/book_import.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tomoread-scan-test-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('BookImportScanService', () {
    test('recursively previews supported files and explains skipped entries', () async {
      final nested = Directory(path.join(root.path, 'nested'));
      final hidden = Directory(path.join(root.path, '.hidden'));
      await nested.create();
      await hidden.create();
      await File(path.join(root.path, 'book.epub')).writeAsBytes([1, 2, 3]);
      await File(path.join(nested.path, 'notes.md')).writeAsString('# Notes');
      await File(path.join(root.path, 'cover.jpg')).writeAsBytes([4, 5]);
      await File(path.join(hidden.path, 'private.txt')).writeAsString('hidden');

      final preview = await const BookImportScanService().scan([
        ImportSource(
          kind: ImportSourceKind.directoryPicker,
          location: root.path,
        ),
      ]);

      expect(preview.supportedCount, 2);
      expect(preview.skippedCount, 2);
      expect(
        preview.requests.map((request) => path.basename(request.sourcePath)),
        containsAll(['book.epub', 'notes.md']),
      );
      expect(
        preview.items.map((item) => item.reason),
        containsAll(['不支持的文件格式', '已忽略隐藏或系统目录']),
      );
    });

    test('enforces size limits and can cancel a directory scan', () async {
      for (var index = 0; index < 5; index++) {
        await File(path.join(root.path, 'book-$index.txt'))
            .writeAsString('123456');
      }
      final sizeLimited = await const BookImportScanService().scan(
        [
          ImportSource(
            kind: ImportSourceKind.directoryPicker,
            location: root.path,
          ),
        ],
        limits: const ImportScanLimits(maxFileBytes: 4),
      );
      expect(sizeLimited.supportedCount, 0);
      expect(sizeLimited.skippedCount, 5);

      final token = ImportCancellationToken();
      final cancelled = await const BookImportScanService().scan(
        [
          ImportSource(
            kind: ImportSourceKind.directoryPicker,
            location: root.path,
          ),
        ],
        cancellationToken: token,
        onProgress: (count) {
          if (count == 1) token.cancel();
        },
      );
      expect(cancelled.cancelled, isTrue);
      expect(cancelled.items, hasLength(1));
    });

    test('does not recurse into excluded private roots', () async {
      final private = Directory(path.join(root.path, 'library'));
      await private.create();
      await File(path.join(private.path, 'managed.epub')).writeAsBytes([1]);

      final preview = await const BookImportScanService().scan(
        [
          ImportSource(
            kind: ImportSourceKind.directoryPicker,
            location: root.path,
          ),
        ],
        excludedRoots: [private.path],
      );

      expect(preview.supportedCount, 0);
      expect(
        preview.items.map((item) => item.reason),
        contains('不会扫描应用私有目录'),
      );
    });
  });
}

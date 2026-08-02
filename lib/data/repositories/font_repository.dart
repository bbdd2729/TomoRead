import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/reading_font.dart';
import '../database/app_database.dart';

class FontReferenceUsage {
  const FontReferenceUsage({required this.global, required this.bookIds});

  final bool global;
  final List<String> bookIds;

  bool get isEmpty => !global && bookIds.isEmpty;
}

class FontRepository {
  FontRepository(
    this._database, {
    Future<Directory> Function()? supportDirectory,
  }) : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final AppDatabase _database;
  final Future<Directory> Function() _supportDirectory;
  static final Set<String> _loadedFontIds = {};

  Future<List<ImportedFont>> listImported() async {
    final database = await _database.database;
    final rows = await database.query('imported_fonts', orderBy: 'family');
    return rows.map(_fromRow).toList();
  }

  Future<ImportedFont?> findById(String id) async {
    final database = await _database.database;
    final rows = await database.query(
      'imported_fonts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  Future<ImportedFont> importFile(
    String sourcePath, {
    String? licenseLabel,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw ArgumentError.value(sourcePath, 'sourcePath', '字体文件不存在');
    }
    final extension = path.extension(sourcePath).toLowerCase().replaceFirst('.', '');
    if (!const {'ttf', 'otf', 'woff', 'woff2'}.contains(extension)) {
      throw const FormatException('仅支持 .ttf、.otf、.woff 和 .woff2 字体。');
    }
    final bytes = await source.readAsBytes();
    final hash = sha256.convert(bytes).toString();
    final database = await _database.database;
    final duplicate = await database.query(
      'imported_fonts',
      where: 'file_hash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    if (duplicate.isNotEmpty) return _fromRow(duplicate.single);

    final id = hash.substring(0, 24);
    final family = _OpenTypeNameReader.family(bytes, extension) ??
        path.basenameWithoutExtension(sourcePath);
    final root = await _supportDirectory();
    final directory = Directory(path.join(root.path, 'fonts'));
    if (!await directory.exists()) await directory.create(recursive: true);
    final storedPath = path.join(directory.path, '$id.$extension');
    await File(storedPath).writeAsBytes(bytes, flush: true);
    final imported = ImportedFont(
      id: id,
      family: family,
      fileName: path.basename(sourcePath),
      filePath: storedPath,
      fileHash: hash,
      format: extension,
      source: source.absolute.path,
      licenseLabel: licenseLabel?.trim().isEmpty == true
          ? null
          : licenseLabel?.trim(),
      createdAt: DateTime.now(),
    );
    await database.insert('imported_fonts', {
      'id': imported.id,
      'family': imported.family,
      'file_name': imported.fileName,
      'file_path': imported.filePath,
      'file_hash': imported.fileHash,
      'format': imported.format,
      'source': imported.source,
      'license_label': imported.licenseLabel,
      'created_at': imported.createdAt.millisecondsSinceEpoch,
    });
    return imported;
  }

  Future<void> ensureLoaded(ReadingFontRef ref) async {
    final id = ref.importedFontId;
    if (id == null || _loadedFontIds.contains(id)) return;
    final font = await findById(id);
    if (font == null) return;
    final data = await File(font.filePath).readAsBytes();
    final loader = FontLoader(ref.runtimeFamily);
    loader.addFont(Future.value(ByteData.sublistView(data)));
    await loader.load();
    _loadedFontIds.add(id);
  }

  Future<String?> epubFontFaceCss(ReadingFontRef ref) async {
    final id = ref.importedFontId;
    if (id == null) return null;
    final font = await findById(id);
    if (font == null) return null;
    final bytes = await File(font.filePath).readAsBytes();
    final mime = switch (font.format) {
      'woff' => 'font/woff',
      'woff2' => 'font/woff2',
      'otf' => 'font/otf',
      _ => 'font/ttf',
    };
    final format = switch (font.format) {
      'woff' => 'woff',
      'woff2' => 'woff2',
      'otf' => 'opentype',
      _ => 'truetype',
    };
    final encoded = base64Encode(bytes);
    return "@font-face{font-family:'${ref.runtimeFamily}';src:url(data:$mime;base64,$encoded) format('$format');font-display:swap;}";
  }

  Future<FontReferenceUsage> references(String fontId) async {
    final database = await _database.database;
    final appRows = await database.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: ['reading_defaults'],
      limit: 1,
    );
    final global = appRows.isNotEmpty &&
        _fontFromSettingsJson(appRows.single['setting_value']) == fontId;
    final overrides = await database.query(
      'book_reading_overrides',
      columns: ['book_id', 'font'],
    );
    final bookIds = overrides
        .where((row) => ReadingFontRef.parse(row['font']).importedFontId == fontId)
        .map((row) => row['book_id']! as String)
        .toList();
    return FontReferenceUsage(global: global, bookIds: bookIds);
  }

  Future<void> delete(
    String fontId, {
    ReadingFontRef? replacement,
  }) async {
    final usage = await references(fontId);
    if (!usage.isEmpty && replacement == null) {
      throw ImportedFontReferenceException(fontId, usage.bookIds);
    }
    if (replacement?.importedFontId == fontId) {
      throw ArgumentError.value(replacement, 'replacement', '替代字体不能是待删除字体');
    }
    final database = await _database.database;
    final font = await findById(fontId);
    if (font == null) return;
    await database.transaction((transaction) async {
      if (replacement != null) {
        if (usage.global) {
          final rows = await transaction.query(
            'app_settings',
            where: 'setting_key = ?',
            whereArgs: ['reading_defaults'],
            limit: 1,
          );
          if (rows.isNotEmpty) {
            final value = jsonDecode(rows.single['setting_value']! as String)
                as Map<String, Object?>;
            value['font'] = replacement.storageValue;
            await transaction.update(
              'app_settings',
              {'setting_value': jsonEncode(value)},
              where: 'setting_key = ?',
              whereArgs: ['reading_defaults'],
            );
          }
        }
        if (usage.bookIds.isNotEmpty) {
          final placeholders = List.filled(usage.bookIds.length, '?').join(',');
          await transaction.rawUpdate(
            'UPDATE book_reading_overrides SET font = ? '
            'WHERE book_id IN ($placeholders)',
            [replacement.storageValue, ...usage.bookIds],
          );
        }
      }
      await transaction.delete(
        'imported_fonts',
        where: 'id = ?',
        whereArgs: [fontId],
      );
    });
    final file = File(font.filePath);
    if (await file.exists()) await file.delete();
    _loadedFontIds.remove(fontId);
  }

  String? _fontFromSettingsJson(Object? source) {
    if (source is! String) return null;
    try {
      final value = jsonDecode(source) as Map<String, Object?>;
      return ReadingFontRef.parse(value['font']).importedFontId;
    } on FormatException {
      return null;
    }
  }

  ImportedFont _fromRow(Map<String, Object?> row) => ImportedFont(
    id: row['id']! as String,
    family: row['family']! as String,
    fileName: row['file_name']! as String,
    filePath: row['file_path']! as String,
    fileHash: row['file_hash']! as String,
    format: row['format']! as String,
    source: row['source']! as String,
    licenseLabel: row['license_label'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
  );
}

class _OpenTypeNameReader {
  static String? family(Uint8List bytes, String format) {
    try {
      if (format == 'woff') return _fromWoff(bytes);
      if (format == 'woff2') return null;
      return _fromSfnt(bytes);
    } on Object {
      return null;
    }
  }

  static String? _fromWoff(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(0) != 0x774F4646) return null;
    final tableCount = data.getUint16(12);
    for (var index = 0; index < tableCount; index++) {
      final offset = 44 + index * 20;
      if (_tag(data.getUint32(offset)) != 'name') continue;
      final tableOffset = data.getUint32(offset + 4);
      final compressedLength = data.getUint32(offset + 8);
      final originalLength = data.getUint32(offset + 12);
      var table = bytes.sublist(tableOffset, tableOffset + compressedLength);
      if (compressedLength != originalLength) {
        table = Uint8List.fromList(ZLibDecoder().convert(table));
      }
      return _fromNameTable(table);
    }
    return null;
  }

  static String? _fromSfnt(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final tableCount = data.getUint16(4);
    for (var index = 0; index < tableCount; index++) {
      final offset = 12 + index * 16;
      if (_tag(data.getUint32(offset)) != 'name') continue;
      final tableOffset = data.getUint32(offset + 8);
      final length = data.getUint32(offset + 12);
      return _fromNameTable(bytes.sublist(tableOffset, tableOffset + length));
    }
    return null;
  }

  static String? _fromNameTable(Uint8List table) {
    final data = ByteData.sublistView(table);
    final count = data.getUint16(2);
    final stringsOffset = data.getUint16(4);
    final candidates = <(int, int, String)>[];
    for (var index = 0; index < count; index++) {
      final offset = 6 + index * 12;
      final platform = data.getUint16(offset);
      final language = data.getUint16(offset + 4);
      final nameId = data.getUint16(offset + 6);
      if (nameId != 1 && nameId != 16) continue;
      final length = data.getUint16(offset + 8);
      final stringOffset = stringsOffset + data.getUint16(offset + 10);
      final valueBytes = table.sublist(stringOffset, stringOffset + length);
      final value = platform == 0 || platform == 3
          ? _utf16Be(valueBytes)
          : latin1.decode(valueBytes, allowInvalid: true);
      final cleaned = value.replaceAll('\u0000', '').trim();
      if (cleaned.isNotEmpty) {
        final score = (nameId == 16 ? 100 : 0) + (language == 0x409 ? 10 : 0);
        candidates.add((score, index, cleaned));
      }
    }
    candidates.sort((left, right) => right.$1.compareTo(left.$1));
    return candidates.isEmpty ? null : candidates.first.$3;
  }

  static String _utf16Be(List<int> bytes) {
    final units = <int>[];
    for (var index = 0; index + 1 < bytes.length; index += 2) {
      units.add(bytes[index] << 8 | bytes[index + 1]);
    }
    return String.fromCharCodes(units);
  }

  static String _tag(int value) => String.fromCharCodes([
    value >> 24 & 0xff,
    value >> 16 & 0xff,
    value >> 8 & 0xff,
    value & 0xff,
  ]);
}

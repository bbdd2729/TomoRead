import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart' as charset;
import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/services/text_decoder_service.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tomoread-decode-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('prefers BOM and strict UTF-8 before legacy detection', () async {
    final utf8File = File('${directory.path}${Platform.pathSeparator}utf8.txt');
    await utf8File.writeAsBytes([0xef, 0xbb, 0xbf, ...utf8.encode('第一章')]);
    final utf16File = File(
      '${directory.path}${Platform.pathSeparator}utf16.txt',
    );
    await utf16File.writeAsBytes([
      0xff,
      0xfe,
      for (final unit in '序章'.codeUnits) ...[unit & 0xff, unit >> 8],
    ]);

    const decoder = TextDecoderService();
    final utf8Result = await decoder.decodeFile(utf8File.path);
    final utf16Result = await decoder.decodeFile(utf16File.path);

    expect(utf8Result.encoding, 'utf-8');
    expect(utf8Result.text, '第一章');
    expect(utf16Result.encoding, 'utf-16le');
    expect(utf16Result.text, '序章');
    expect(utf16Result.requiresUserConfirmation, isFalse);
  });

  test('supports an explicit GBK override through a licensed codec', () async {
    final file = File('${directory.path}${Platform.pathSeparator}gbk.txt');
    await file.writeAsBytes(charset.gbk.encode('第一章 开始'));

    final result = await const TextDecoderService().decodeFile(
      file.path,
      encodingOverride: 'gbk',
    );

    expect(result.encoding, 'gbk');
    expect(result.text, '第一章 开始');
    expect(result.confidence, 1);
  });
}

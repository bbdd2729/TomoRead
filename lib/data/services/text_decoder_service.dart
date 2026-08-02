import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:charset/charset.dart' as charset;
import 'package:charset_converter/charset_converter.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../../domain/models/text_content_profile.dart';

const supportedTextEncodings = <String>[
  'utf-8',
  'utf-16le',
  'utf-16be',
  'gb18030',
  'gbk',
  'big5',
  'shift_jis',
  'euc-kr',
  'windows-1252',
];

class TextDecoderService {
  const TextDecoderService();

  Future<TextDecodeResult> decodeFile(
    String filePath, {
    String? encodingOverride,
  }) => startDecodeFile(
    filePath,
    encodingOverride: encodingOverride,
  ).result;

  TextDecodeJob startDecodeFile(
    String filePath, {
    String? encodingOverride,
  }) => TextDecodeJob._start(filePath, encodingOverride);
}

class TextDecodeJob {
  TextDecodeJob._(
    this._result,
    this._completer,
    this._isolate,
    this._receivePort,
  );

  final Future<TextDecodeResult> _result;
  final Completer<TextDecodeResult> _completer;
  final Future<Isolate> _isolate;
  final ReceivePort _receivePort;
  var _cancelled = false;

  Future<TextDecodeResult> get result => _result;

  static TextDecodeJob _start(String filePath, String? encodingOverride) {
    final receivePort = ReceivePort();
    final completer = Completer<TextDecodeResult>();
    late final TextDecodeJob job;
    receivePort.listen((message) {
      if (job._cancelled || completer.isCompleted) return;
      if (message is TextDecodeResult) {
        completer.complete(message);
      } else if (message is Map && message['error'] is String) {
        completer.completeError(TextDecodeException(message['error']! as String));
      }
      receivePort.close();
    });
    final isolate = Isolate.spawn<(
      SendPort,
      String,
      String?,
      RootIsolateToken?
    )>(
      _decodeFileIsolate,
      (
        receivePort.sendPort,
        filePath,
        encodingOverride,
        RootIsolateToken.instance,
      ),
      errorsAreFatal: true,
    );
    job = TextDecodeJob._(completer.future, completer, isolate, receivePort);
    unawaited(
      isolate.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
          receivePort.close();
        },
      ),
    );
    return job;
  }

  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    (await _isolate).kill(priority: Isolate.immediate);
    _receivePort.close();
    if (!_completer.isCompleted) {
      _completer.completeError(const TextDecodeException('文本解码已取消。'));
    }
  }
}

class TextDecodeException implements Exception {
  const TextDecodeException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<void> _decodeFileIsolate(
  (SendPort, String, String?, RootIsolateToken?) request,
) async {
  try {
    final token = request.$4;
    if (token != null) {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    }
    final bytes = await File(request.$2).readAsBytes();
    request.$1.send(await _decodeBytes(bytes, request.$3));
  } on Object catch (error) {
    request.$1.send({'error': error.toString()});
  }
}

Future<TextDecodeResult> _decodeBytes(
  Uint8List bytes,
  String? override,
) async {
  final contentHash = sha256.convert(bytes).toString();
  if (override != null) {
    final normalized = override.trim().toLowerCase();
    if (!supportedTextEncodings.contains(normalized)) {
      throw TextDecodeException('不支持的文本编码：$override');
    }
    final text = await _decodeWith(normalized, bytes);
    return _result(
      text,
      normalized,
      1,
      contentHash,
      requiresConfirmation: false,
    );
  }
  final bom = _bomEncoding(bytes);
  if (bom != null) {
    return _result(
      await _decodeWith(bom, bytes),
      bom,
      1,
      contentHash,
      requiresConfirmation: false,
    );
  }
  if (_looksBinary(bytes)) {
    throw const TextDecodeException('文件包含过多二进制控制字节，无法作为文本导入。');
  }
  try {
    final text = utf8.decode(bytes, allowMalformed: false);
    return _result(
      text,
      'utf-8',
      1,
      contentHash,
      requiresConfirmation: false,
    );
  } on FormatException {
    // Continue with licensed legacy codecs.
  }

  final candidates = <({String encoding, String text, double score})>[];
  for (final encoding in supportedTextEncodings.skip(3)) {
    if (encoding == 'gbk') continue;
    try {
      final text = await _decodeWith(encoding, bytes);
      candidates.add((encoding: encoding, text: text, score: _score(text, encoding)));
    } on Object {
      // Invalid byte sequences eliminate the candidate.
    }
  }
  if (candidates.isEmpty) {
    throw const TextDecodeException('无法识别文本编码，请确认文件不是受保护或损坏的二进制文件。');
  }
  candidates.sort((a, b) => b.score.compareTo(a.score));
  final best = candidates.first;
  final second = candidates.length > 1 ? candidates[1].score : 0;
  final margin = (best.score - second).clamp(0, 1).toDouble();
  final confidence = (best.score * .65 + margin * .35).clamp(0, 1).toDouble();
  return _result(
    best.text,
    best.encoding,
    confidence,
    contentHash,
    requiresConfirmation: confidence < .72,
    candidates: candidates.take(4).map((item) => item.encoding).toList(),
  );
}

TextDecodeResult _result(
  String text,
  String encoding,
  double confidence,
  String contentHash, {
  required bool requiresConfirmation,
  List<String> candidates = const [],
}) {
  final replacements = '\uFFFD'.allMatches(text).length;
  final hasReplacements = replacements > 0;
  return TextDecodeResult(
    text: text,
    encoding: encoding,
    confidence: confidence,
    hasReplacementCharacters: hasReplacements,
    preview: text.substring(0, text.length.clamp(0, 2048).toInt()),
    contentHash: contentHash,
    requiresUserConfirmation: requiresConfirmation || hasReplacements,
    candidates: candidates,
  );
}

Future<String> _decodeWith(String encoding, Uint8List source) async {
  final bytes = source.toList(growable: false);
  return switch (encoding) {
    'utf-8' => utf8.decode(_withoutUtf8Bom(bytes), allowMalformed: false),
    'utf-16le' => _decodeUtf16(bytes, littleEndian: true),
    'utf-16be' => _decodeUtf16(bytes, littleEndian: false),
    'gb18030' => await CharsetConverter.decode('GB18030', source),
    'gbk' => charset.gbk.decode(bytes),
    'big5' => await CharsetConverter.decode('Big5', source),
    'shift_jis' => charset.shiftJis.decode(bytes),
    'euc-kr' => charset.eucKr.decode(bytes),
    'windows-1252' => charset.windows1252.decode(bytes),
    _ => throw TextDecodeException('不支持的文本编码：$encoding'),
  };
}

String _decodeUtf16(List<int> source, {required bool littleEndian}) {
  var offset = 0;
  if (source.length >= 2 &&
      ((source[0] == 0xff && source[1] == 0xfe) ||
          (source[0] == 0xfe && source[1] == 0xff))) {
    offset = 2;
  }
  if ((source.length - offset).isOdd) {
    throw const FormatException('Odd UTF-16 byte count');
  }
  final units = <int>[];
  for (var index = offset; index < source.length; index += 2) {
    units.add(
      littleEndian
          ? source[index] | source[index + 1] << 8
          : source[index] << 8 | source[index + 1],
    );
  }
  return String.fromCharCodes(units);
}

List<int> _withoutUtf8Bom(List<int> bytes) =>
    bytes.length >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf
    ? bytes.sublist(3)
    : bytes;

String? _bomEncoding(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf) {
    return 'utf-8';
  }
  if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
    return 'utf-16le';
  }
  if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
    return 'utf-16be';
  }
  return null;
}

bool _looksBinary(Uint8List bytes) {
  if (bytes.isEmpty) return false;
  final sample = bytes.take(8192);
  final controls = sample.where((value) =>
      value == 0 || (value < 0x09 || (value > 0x0d && value < 0x20))).length;
  return controls / sample.length > .08;
}

double _score(String text, String encoding) {
  if (text.isEmpty) return 0;
  var printable = 0;
  var expectedScript = 0;
  var controls = 0;
  for (final rune in text.runes.take(20000)) {
    if (rune == 9 || rune == 10 || rune == 13 || rune >= 32) printable++;
    if (rune < 9 || (rune > 13 && rune < 32)) controls++;
    if (encoding == 'gb18030' || encoding == 'gbk' || encoding == 'big5') {
      if (rune >= 0x3400 && rune <= 0x9fff) expectedScript++;
    } else if (encoding == 'shift_jis') {
      if ((rune >= 0x3040 && rune <= 0x30ff) ||
          (rune >= 0x4e00 && rune <= 0x9fff)) {
        expectedScript++;
      }
    } else if (encoding == 'euc-kr') {
      if (rune >= 0xac00 && rune <= 0xd7af) expectedScript++;
    }
  }
  final length = text.runes.take(20000).length;
  final printableRatio = printable / length;
  final scriptRatio = expectedScript / length;
  return (printableRatio * .7 + scriptRatio.clamp(0, .3) - controls / length)
      .clamp(0, 1)
      .toDouble();
}

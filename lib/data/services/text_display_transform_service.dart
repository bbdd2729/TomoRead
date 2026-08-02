import 'dart:async';
import 'dart:isolate';

import 'package:opencc/opencc.dart' show ZhConverter;

import '../../domain/models/display_projection.dart';

class TextDisplayTransformService {
  const TextDisplayTransformService();

  Future<DisplayProjection> project({
    required String bookId,
    required String rawText,
    required TextProjectionSettings settings,
    List<TextDisplayRule> rules = const [],
  }) => startProjection(
    bookId: bookId,
    rawText: rawText,
    settings: settings,
    rules: rules,
  ).result;

  TextProjectionJob startProjection({
    required String bookId,
    required String rawText,
    required TextProjectionSettings settings,
    List<TextDisplayRule> rules = const [],
  }) => TextProjectionJob._start(
    bookId: bookId,
    rawText: rawText,
    settings: settings,
    rules: rules,
  );
}

class TextProjectionJob {
  TextProjectionJob._(
    this._completer,
    this._isolate,
    this._receivePort,
  );

  final Completer<DisplayProjection> _completer;
  final Future<Isolate> _isolate;
  final ReceivePort _receivePort;
  var _cancelled = false;

  Future<DisplayProjection> get result => _completer.future;

  static TextProjectionJob _start({
    required String bookId,
    required String rawText,
    required TextProjectionSettings settings,
    required List<TextDisplayRule> rules,
  }) {
    final receivePort = ReceivePort();
    final completer = Completer<DisplayProjection>();
    late final TextProjectionJob job;
    receivePort.listen((message) {
      if (job._cancelled || completer.isCompleted) return;
      if (message is DisplayProjection) {
        completer.complete(message);
      } else if (message is Map && message['error'] is String) {
        completer.completeError(TextProjectionException(message['error']! as String));
      }
      receivePort.close();
    });
    final isolate = Isolate.spawn<
      (SendPort, String, String, TextProjectionSettings, List<TextDisplayRule>)
    >(
      _projectInIsolate,
      (receivePort.sendPort, bookId, rawText, settings, rules),
      errorsAreFatal: true,
    );
    job = TextProjectionJob._(completer, isolate, receivePort);
    unawaited(
      isolate.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) completer.completeError(error, stackTrace);
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
      _completer.completeError(const TextProjectionException('文本投影已取消。'));
    }
  }
}

class TextProjectionException implements Exception {
  const TextProjectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

void _projectInIsolate(
  (SendPort, String, String, TextProjectionSettings, List<TextDisplayRule>)
  request,
) {
  try {
    request.$1.send(
      _buildProjection(
        bookId: request.$2,
        rawText: request.$3,
        settings: request.$4,
        rules: request.$5,
      ),
    );
  } on Object catch (error) {
    request.$1.send({'error': error.toString()});
  }
}

DisplayProjection _buildProjection({
  required String bookId,
  required String rawText,
  required TextProjectionSettings settings,
  required List<TextDisplayRule> rules,
}) {
  var buffer = _ProjectionBuffer.identity(rawText);
  if (settings.chineseConversion != ChineseConversionMode.off &&
      rawText.isNotEmpty) {
    final config = switch (settings.chineseConversion) {
      ChineseConversionMode.traditionalToSimplified => 't2s',
      ChineseConversionMode.simplifiedToTraditional => 's2t',
      ChineseConversionMode.simplifiedToTaiwan => 's2tw',
      ChineseConversionMode.simplifiedToHongKong => 's2hk',
      ChineseConversionMode.off => throw StateError('Conversion is disabled'),
    };
    final converter = ZhConverter(config, large: true);
    try {
      buffer = buffer.replaceConservatively(converter.convert(buffer.text));
    } finally {
      converter.dispose();
    }
  }
  if (settings.widthMode != CharacterWidthMode.unchanged) {
    buffer = buffer.convertWidth(settings);
  }
  final applicable = rules.where((rule) => rule.appliesTo(bookId)).toList()
    ..sort((left, right) {
      final scope = (left.bookId == null ? 1 : 0).compareTo(
        right.bookId == null ? 1 : 0,
      );
      if (scope != 0) return scope;
      final priority = right.priority.compareTo(left.priority);
      if (priority != 0) return priority;
      final length = right.findText.length.compareTo(left.findText.length);
      if (length != 0) return length;
      return left.createdAt.compareTo(right.createdAt);
    });
  if (applicable.isNotEmpty) buffer = buffer.replaceLiterals(applicable);
  return buffer.toProjection(rawText);
}

class _ProjectionBuffer {
  const _ProjectionBuffer(this.text, this.cells);

  factory _ProjectionBuffer.identity(String text) => _ProjectionBuffer(
    text,
    [
      for (var index = 0; index < text.length; index++)
        ProjectionCell(rawStart: index, rawEnd: index + 1, isExact: true),
    ],
  );

  final String text;
  final List<ProjectionCell> cells;

  _ProjectionBuffer replaceConservatively(String output) {
    if (output == text) return this;
    var prefix = 0;
    final prefixLimit = text.length < output.length ? text.length : output.length;
    while (prefix < prefixLimit && text.codeUnitAt(prefix) == output.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < text.length - prefix &&
        suffix < output.length - prefix &&
        text.codeUnitAt(text.length - suffix - 1) ==
            output.codeUnitAt(output.length - suffix - 1)) {
      suffix++;
    }
    final inputMiddleLength = text.length - prefix - suffix;
    final outputMiddleLength = output.length - prefix - suffix;
    final mapped = <ProjectionCell>[...cells.take(prefix)];
    if (outputMiddleLength > 0) {
      if (inputMiddleLength == outputMiddleLength) {
        mapped.addAll(cells.skip(prefix).take(inputMiddleLength));
      } else {
        final middle = cells.skip(prefix).take(inputMiddleLength).toList();
        final rawStart = middle.isEmpty
            ? (prefix == 0 ? 0 : cells[prefix - 1].rawEnd)
            : middle.first.rawStart;
        final rawEnd = middle.isEmpty ? rawStart : middle.last.rawEnd;
        for (var index = 0; index < outputMiddleLength; index++) {
          mapped.add(
            ProjectionCell(rawStart: rawStart, rawEnd: rawEnd, isExact: false),
          );
        }
      }
    }
    if (suffix > 0) mapped.addAll(cells.skip(cells.length - suffix));
    return _ProjectionBuffer(output, mapped);
  }

  _ProjectionBuffer convertWidth(TextProjectionSettings settings) {
    final units = text.codeUnits.toList();
    for (var index = 0; index < units.length; index++) {
      final unit = units[index];
      final isLetter =
          (unit >= 0x41 && unit <= 0x5a) || (unit >= 0x61 && unit <= 0x7a);
      final isNumber = unit >= 0x30 && unit <= 0x39;
      final fullWidthLetter =
          (unit >= 0xff21 && unit <= 0xff3a) ||
          (unit >= 0xff41 && unit <= 0xff5a);
      final fullWidthNumber = unit >= 0xff10 && unit <= 0xff19;
      final allowed =
          (settings.convertLetters && (isLetter || fullWidthLetter)) ||
          (settings.convertNumbers && (isNumber || fullWidthNumber));
      if (!allowed) continue;
      units[index] = switch (settings.widthMode) {
        CharacterWidthMode.toFullWidth when unit >= 0x21 && unit <= 0x7e =>
          unit + 0xfee0,
        CharacterWidthMode.toHalfWidth
            when unit >= 0xff01 && unit <= 0xff5e =>
          unit - 0xfee0,
        _ => unit,
      };
    }
    return _ProjectionBuffer(String.fromCharCodes(units), cells);
  }

  _ProjectionBuffer replaceLiterals(List<TextDisplayRule> rules) {
    final output = StringBuffer();
    final mapped = <ProjectionCell>[];
    var index = 0;
    while (index < text.length) {
      TextDisplayRule? match;
      for (final rule in rules) {
        if (text.startsWith(rule.findText, index)) {
          match = rule;
          break;
        }
      }
      if (match == null) {
        output.writeCharCode(text.codeUnitAt(index));
        mapped.add(cells[index]);
        index++;
        continue;
      }
      output.write(match.replaceText);
      final sourceCells = cells
          .skip(index)
          .take(match.findText.length)
          .toList();
      if (match.replaceText.length == match.findText.length) {
        mapped.addAll(sourceCells);
      } else if (match.replaceText.isNotEmpty) {
        final rawStart = sourceCells.first.rawStart;
        final rawEnd = sourceCells.last.rawEnd;
        for (var offset = 0; offset < match.replaceText.length; offset++) {
          mapped.add(
            ProjectionCell(rawStart: rawStart, rawEnd: rawEnd, isExact: false),
          );
        }
      }
      index += match.findText.length;
    }
    return _ProjectionBuffer(output.toString(), mapped);
  }

  DisplayProjection toProjection(String rawText) => DisplayProjection(
    rawText: rawText,
    displayText: text,
    mappingCells: cells,
    segments: _segments(cells),
  );

  List<ProjectionSegment> _segments(List<ProjectionCell> values) {
    if (values.isEmpty) return const [];
    final result = <ProjectionSegment>[];
    var start = 0;
    for (var index = 1; index <= values.length; index++) {
      final previous = values[index - 1];
      final continues = index < values.length &&
          values[index].isExact == previous.isExact &&
          (previous.isExact
              ? previous.rawEnd == values[index].rawStart
              : previous.rawStart == values[index].rawStart &&
                    previous.rawEnd == values[index].rawEnd);
      if (continues) continue;
      result.add(
        ProjectionSegment(
          rawStart: values[start].rawStart,
          rawEnd: previous.rawEnd,
          displayStart: start,
          displayEnd: index,
          isExact: previous.isExact,
        ),
      );
      start = index;
    }
    return result;
  }
}

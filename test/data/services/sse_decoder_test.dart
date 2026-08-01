import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/services/sse_decoder.dart';

void main() {
  test('decodes fragmented UTF-8, comments, and multiline data', () async {
    final source = utf8.encode(
      ': keep alive\r\n'
      'event: message\r\n'
      'id: 7\r\n'
      'data: {"text":"你\r\n'
      'data: 好"}\r\n'
      '\r\n'
      'data: [DONE]\r\n\r\n',
    );
    final chunks = <List<int>>[
      source.sublist(0, 19),
      source.sublist(19, 37),
      source.sublist(37, 52),
      source.sublist(52),
    ];

    final events = await const SseDecoder()
        .decode(Stream.fromIterable(chunks))
        .toList();

    expect(events, hasLength(2));
    expect(events.first.event, 'message');
    expect(events.first.id, '7');
    expect(events.first.data, '{"text":"你\n好"}');
    expect(events.last.data, '[DONE]');
  });

  test('flushes a final event without a trailing empty line', () async {
    final events = await const SseDecoder()
        .decode(Stream.value(utf8.encode('data: final')))
        .toList();

    expect(events.single.data, 'final');
  });
}

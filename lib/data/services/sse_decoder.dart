import 'dart:convert';

class SseEvent {
  const SseEvent({required this.data, this.event, this.id});

  final String data;
  final String? event;
  final String? id;
}

class SseDecoder {
  const SseDecoder();

  Stream<SseEvent> decode(Stream<List<int>> source) async* {
    final dataLines = <String>[];
    String? eventName;
    String? eventId;

    await for (final line
        in source.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (dataLines.isNotEmpty) {
          yield SseEvent(
            data: dataLines.join('\n'),
            event: eventName,
            id: eventId,
          );
        }
        dataLines.clear();
        eventName = null;
        continue;
      }
      if (line.startsWith(':')) continue;
      final separator = line.indexOf(':');
      final field = separator < 0 ? line : line.substring(0, separator);
      var value = separator < 0 ? '' : line.substring(separator + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      switch (field) {
        case 'data':
          dataLines.add(value);
        case 'event':
          eventName = value;
        case 'id':
          eventId = value;
      }
    }
    if (dataLines.isNotEmpty) {
      yield SseEvent(data: dataLines.join('\n'), event: eventName, id: eventId);
    }
  }
}

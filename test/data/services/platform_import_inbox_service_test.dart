import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/data/services/platform_import_inbox_service.dart';
import 'package:tomoread/domain/models/book_import.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.tomoread/import_inbox.test');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('combines supported command-line paths with validated native sources', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'getInitialSources') return null;
          return [
            {
              'kind': 'androidShare',
              'path': '/cache/incoming/book.epub',
              'displayName': 'Shared book.epub',
              'mimeType': 'application/epub+zip',
              'temporary': true,
            },
            {'error': '一个分享文件无法读取。'},
          ];
        });
    final service = PlatformImportInboxService(
      initialArguments: const [
        '--trace-startup',
        '/books/novel.pdf',
        '/books/cover.jpg',
      ],
      channel: channel,
    );
    addTearDown(service.dispose);
    final events = <PlatformImportEvent>[];
    final subscription = service.events.listen(events.add);
    addTearDown(subscription.cancel);

    await service.initialize();
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(2));
    expect(events.first.sources.single.kind, ImportSourceKind.commandLine);
    expect(events.first.sources.single.location, '/books/novel.pdf');
    expect(events.last.sources.single.kind, ImportSourceKind.androidShare);
    expect(events.last.sources.single.temporary, isTrue);
    expect(events.last.errors, ['一个分享文件无法读取。']);
  });

  test('reports malformed native entries without creating import requests', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => [
          {'kind': 'unknown', 'path': '/tmp/book.epub'},
          {'kind': 'desktopDrop', 'path': ''},
        ]);
    final service = PlatformImportInboxService(channel: channel);
    addTearDown(service.dispose);
    final eventFuture = service.events.first;

    await service.initialize();
    final event = await eventFuture;

    expect(event.sources, isEmpty);
    expect(event.errors, hasLength(2));
  });
}

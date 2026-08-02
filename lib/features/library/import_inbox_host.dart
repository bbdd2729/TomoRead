import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/providers.dart';
import '../../data/services/book_import_service.dart';
import '../../data/services/platform_import_inbox_service.dart';
import 'book_import_preview_dialog.dart';
import 'import_result_handler.dart';
import 'import_workflow_controller.dart';

class ImportInboxHost extends ConsumerStatefulWidget {
  const ImportInboxHost({
    super.key,
    required this.initialArguments,
    required this.builder,
    this.inboxService,
  });

  final List<String> initialArguments;
  final Widget Function(Future<void> Function() pickFiles) builder;
  final PlatformImportInboxService? inboxService;

  @override
  ConsumerState<ImportInboxHost> createState() => _ImportInboxHostState();
}

class _ImportInboxHostState extends ConsumerState<ImportInboxHost> {
  late final PlatformImportInboxService _inbox;
  late final ImportWorkflowController _controller;
  late final bool _ownsInbox;
  final Queue<PlatformImportEvent> _pending = Queue();
  StreamSubscription<PlatformImportEvent>? _subscription;
  var _processing = false;

  @override
  void initState() {
    super.initState();
    _ownsInbox = widget.inboxService == null;
    _inbox =
        widget.inboxService ??
        PlatformImportInboxService(initialArguments: widget.initialArguments);
    _controller = ImportWorkflowController.forService(
      ref.read(bookImportServiceProvider),
    );
    _subscription = _inbox.events.listen(_enqueue);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_inbox.initialize());
    });
  }

  void _enqueue(PlatformImportEvent event) {
    if (!mounted || event.isEmpty) return;
    _pending.add(event);
    unawaited(_processPending());
  }

  Future<void> _processPending() async {
    if (_processing || !mounted) return;
    _processing = true;
    try {
      while (_pending.isNotEmpty && mounted) {
        final event = _pending.removeFirst();
        for (final error in event.errors) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error)));
        }
        if (event.sources.isEmpty) continue;
        _controller.reset();
        final dialog = showDialog<List<BookImportResult>>(
          context: context,
          barrierDismissible: false,
          builder: (context) => BookImportPreviewDialog(
            controller: _controller,
          ),
        );
        unawaited(_controller.prepare(event.sources));
        final initialResults = await dialog;
        if (!mounted || initialResults == null) continue;
        final results = await resolveImportResults(context, ref, initialResults);
        if (!mounted) return;
        if (results.any(
          (result) => result.status == BookImportStatus.imported,
        )) {
          ref.invalidate(libraryBooksProvider);
        }
        showImportSummary(context, results);
      }
    } finally {
      _processing = false;
      if (_pending.isNotEmpty && mounted) unawaited(_processPending());
    }
  }

  Future<void> _pickFiles() async {
    final sources = await ref.read(bookImportServiceProvider).pickImportSources();
    if (sources.isNotEmpty) {
      _enqueue(PlatformImportEvent(sources: sources));
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _controller.dispose();
    if (_ownsInbox) unawaited(_inbox.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_pickFiles);
}

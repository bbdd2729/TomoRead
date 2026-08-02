import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/models/epub_interaction.dart';

typedef EpubExternalUriLauncher = Future<bool> Function(Uri uri);

Future<bool> _launchExternalUri(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

Future<void> presentEpubInteraction(
  BuildContext context,
  EpubInteraction interaction, {
  EpubExternalUriLauncher launcher = _launchExternalUri,
}) async {
  switch (interaction.kind) {
    case EpubInteractionKind.externalLinkRequested:
      final uri = interaction.externalUri!;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => EpubExternalLinkDialog(uri: uri),
      );
      if (confirmed != true) return;
      final launched = await launcher(uri);
      if (!launched && context.mounted) {
        _showMessage(context, '无法使用系统应用打开此链接。');
      }
      return;
    case EpubInteractionKind.blockedLink:
      _showMessage(context, '已拦截不安全或不受支持的链接。');
      return;
    case EpubInteractionKind.imageFailed:
    case EpubInteractionKind.interactionError:
      _showMessage(context, interaction.message ?? 'EPUB 资源暂时无法显示。');
      return;
    case EpubInteractionKind.footnoteOpened:
    case EpubInteractionKind.footnoteClosed:
    case EpubInteractionKind.imageOpened:
    case EpubInteractionKind.imageClosed:
    case EpubInteractionKind.internalLink:
    case EpubInteractionKind.internalBack:
      return;
  }
}

void reportInvalidEpubInteraction(BuildContext context) {
  _showMessage(context, '已拦截无效的 EPUB 交互消息。');
}

void _showMessage(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class EpubExternalLinkDialog extends StatelessWidget {
  const EpubExternalLinkDialog({super.key, required this.uri});

  final Uri uri;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('打开外部链接？'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('此链接将交给系统浏览器或其他应用打开：'),
        const SizedBox(height: 12),
        SelectableText(uri.toString()),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('继续打开'),
      ),
    ],
  );
}

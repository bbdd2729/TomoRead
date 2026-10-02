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
        _showMessage(context, 'لا يمكن فتح هذا الرابط باستخدام تطبيق النظام.');
      }
      return;
    case EpubInteractionKind.blockedLink:
      _showMessage(context, 'تم حظر الروابط غير الآمنة أو غير المدعومة.');
      return;
    case EpubInteractionKind.imageFailed:
    case EpubInteractionKind.interactionError:
      _showMessage(context, interaction.message ?? 'موارد EPUB غير متاحة مؤقتًا.');
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
  _showMessage(context, 'تم حظر رسالة تفاعل EPUB غير صالحة.');
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
    title: const Text('هل تريد فتح رابط خارجي ؟'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('سيتم إرسال هذا الرابط إلى متصفح النظام أو تطبيق آخر لفتحه:'),
        const SizedBox(height: 12),
        SelectableText(uri.toString()),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('متابعة الفتح'),
      ),
    ],
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../domain/models/chat_models.dart';
import '../../../domain/models/visual_artifact.dart';
import '../../visualization/visual_artifact_widgets.dart';

class ChatMessagePartView extends StatelessWidget {
  const ChatMessagePartView({
    super.key,
    required this.part,
    required this.onOpenCitation,
  });

  final ChatMessagePart part;
  final ValueChanged<ChatCitation> onOpenCitation;

  @override
  Widget build(BuildContext context) {
    final value = part;
    return switch (value) {
      ChatTextPart() => SelectionArea(child: MarkdownBody(data: value.text)),
      ChatReasoningPart() => _ReasoningPartView(part: value),
      ChatQuotePart() => _QuotePartView(part: value),
      ChatToolCallPart() => _ToolPartView(
        title: value.displayName,
        icon: Icons.build_outlined,
        status: value.status,
        argumentsJson: value.argumentsJson,
        result: value.result,
        error: value.error,
        durationMillis: value.durationMillis,
      ),
      ChatSkillCallPart() => _ToolPartView(
        title: value.skillName,
        icon: Icons.auto_awesome_outlined,
        status: value.status,
        argumentsJson: value.argumentsJson,
        result: value.result,
        error: value.error,
        durationMillis: value.durationMillis,
        skill: true,
      ),
      ChatCitationPart() => _CitationPartView(
        citation: value.citation,
        onOpen: onOpenCitation,
      ),
      ChatArtifactPart() => _ArtifactPartView(
        part: value,
        onOpenCitation: onOpenCitation,
      ),
      ChatNoticePart() => _NoticePartView(part: value),
      ChatAbortedPart() => _AbortedPartView(part: value),
    };
  }
}

class _ArtifactPartView extends StatelessWidget {
  const _ArtifactPartView({required this.part, required this.onOpenCitation});

  final ChatArtifactPart part;
  final ValueChanged<ChatCitation> onOpenCitation;

  @override
  Widget build(BuildContext context) {
    VisualArtifactKind? kind;
    for (final value in VisualArtifactKind.values) {
      if (value.name == part.artifactType) kind = value;
    }
    if (kind == null) {
      return ListTile(
        leading: const Icon(Icons.data_object),
        title: Text(part.title),
        subtitle: Text('暂不支持的 Artifact 类型：${part.artifactType}'),
      );
    }
    final artifact = VisualArtifact(
      id: part.artifactId ?? part.id,
      bookId: part.bookId ?? '',
      kind: kind,
      scope: VisualArtifactScope.currentChapter,
      title: part.title,
      contentHash: '',
      payloadJson: part.payloadJson,
      createdAt: part.createdAt,
    );
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.account_tree_outlined),
        title: Text(part.title),
        subtitle: Text(
          kind == VisualArtifactKind.wordCloud
              ? '词云 Artifact'
              : '思维导图 Artifact',
        ),
        children: [
          SizedBox(
            height: 420,
            child: VisualArtifactView(
              artifact: artifact,
              onOpenCitation: (citation) => onOpenCitation(
                ChatCitation(
                  id: 'artifact-${part.id}-${citation.locator}',
                  messageId: part.messageId,
                  ordinal: 1,
                  bookId: citation.bookId,
                  href: citation.href,
                  locator: citation.locator,
                  chapterIndex: citation.chapterIndex,
                  chapterTitle: citation.chapterTitle,
                  quote: citation.quote,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReasoningPartView extends StatelessWidget {
  const _ReasoningPartView({required this.part});

  final ChatReasoningPart part;

  @override
  Widget build(BuildContext context) {
    final running = part.status == ChatPartStatus.running;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(7),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: ValueKey('${part.id}-${part.status.name}'),
        initiallyExpanded: running,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        leading: running
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.psychology_outlined, size: 20),
        title: Text(running ? '思考中' : '思考摘要'),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectionArea(child: MarkdownBody(data: part.text)),
          ),
        ],
      ),
    );
  }
}

class _QuotePartView extends StatelessWidget {
  const _QuotePartView({required this.part});

  final ChatQuotePart part;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: .55),
        border: Border(left: BorderSide(color: colors.secondary, width: 3)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${part.bookTitle} · ${part.chapterTitle ?? '当前章节'}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            Text(part.quote, maxLines: 6, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _ToolPartView extends StatelessWidget {
  const _ToolPartView({
    required this.title,
    required this.icon,
    required this.status,
    required this.argumentsJson,
    this.result,
    this.error,
    this.durationMillis,
    this.skill = false,
  });

  final String title;
  final IconData icon;
  final ChatPartStatus status;
  final String argumentsJson;
  final String? result;
  final String? error;
  final int? durationMillis;
  final bool skill;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final running =
        status == ChatPartStatus.pending || status == ChatPartStatus.running;
    final failed = status == ChatPartStatus.error;
    final detail = error ?? result;
    return Material(
      color: skill
          ? colors.tertiaryContainer.withValues(alpha: .35)
          : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(7),
        side: BorderSide(color: failed ? colors.error : colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: ValueKey('$title-${status.name}'),
        initiallyExpanded: failed,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        leading: running
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(failed ? Icons.error_outline : icon, size: 20),
        title: Text(title, style: Theme.of(context).textTheme.titleSmall),
        subtitle: Text(switch (status) {
          ChatPartStatus.pending => '等待执行',
          ChatPartStatus.running => '正在执行',
          ChatPartStatus.completed =>
            durationMillis == null ? '已完成' : '已完成 · ${durationMillis}ms',
          ChatPartStatus.error => '执行失败',
        }),
        children: [
          if (argumentsJson.trim().isNotEmpty) ...[
            _TechnicalDetail(label: '参数', value: argumentsJson),
            if (detail != null) const SizedBox(height: 8),
          ],
          if (detail != null)
            _TechnicalDetail(label: failed ? '错误' : '结果', value: detail),
        ],
      ),
    );
  }
}

class _TechnicalDetail extends StatelessWidget {
  const _TechnicalDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        SelectionArea(
          child: Text(
            value,
            maxLines: 12,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ),
      ],
    ),
  );
}

class _CitationPartView extends StatelessWidget {
  const _CitationPartView({required this.citation, required this.onOpen});

  final ChatCitation citation;
  final ValueChanged<ChatCitation> onOpen;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    leading: CircleAvatar(radius: 12, child: Text('${citation.ordinal}')),
    title: Text(citation.chapterTitle ?? '引用原文'),
    subtitle: Text(
      citation.quote,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: const Icon(Icons.open_in_new, size: 17),
    onTap: () => onOpen(citation),
  );
}

class _NoticePartView extends StatelessWidget {
  const _NoticePartView({required this.part});

  final ChatNoticePart part;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: part.level == ChatNoticeLevel.error
            ? colors.errorContainer
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Icon(
              part.level == ChatNoticeLevel.error
                  ? Icons.error_outline
                  : Icons.info_outline,
              size: 19,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(part.message)),
          ],
        ),
      ),
    );
  }
}

class _AbortedPartView extends StatelessWidget {
  const _AbortedPartView({required this.part});

  final ChatAbortedPart part;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.stop_circle_outlined, size: 18),
      const SizedBox(width: 7),
      Text(part.reason, style: Theme.of(context).textTheme.labelMedium),
    ],
  );
}

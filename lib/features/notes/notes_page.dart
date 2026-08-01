import 'package:flutter/material.dart';

import '../../shared/widgets/page_header.dart';

class NotesPage extends StatelessWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 760;
      final detail = const _NoteDetail();
      if (compact) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 36),
          children: [
            const PageHeader(title: '笔记', subtitle: '回顾你的高亮、注释与思考。'),
            const SizedBox(height: 24),
            const _NoteFilters(),
            const SizedBox(height: 24),
            detail,
          ],
        );
      }

      return Row(
        children: [
          const SizedBox(width: 300, child: _NotesSidebar()),
          const VerticalDivider(width: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(44, 40, 44, 56),
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: detail,
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _NotesSidebar extends StatelessWidget {
  const _NotesSidebar();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '笔记',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(height: 4),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('从阅读中沉淀想法。'),
          ),
          SizedBox(height: 20),
          _NoteFilters(),
          SizedBox(height: 24),
          ListTile(
            title: Text('真正的阅读是一种主动的工作。'),
            subtitle: Text('阅读的技艺 · 第二章'),
            selected: true,
          ),
          ListTile(title: Text('检视阅读帮助我们掌握轮廓。'), subtitle: Text('阅读的技艺 · 第四章')),
        ],
      ),
    );
  }
}

class _NoteFilters extends StatelessWidget {
  const _NoteFilters();

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: const [
      FilterChip(
        selected: true,
        onSelected: _ignoreSelection,
        avatar: Icon(Icons.highlight_alt),
        label: Text('高亮 12'),
      ),
      FilterChip(
        selected: false,
        onSelected: _ignoreSelection,
        avatar: Icon(Icons.sticky_note_2_outlined),
        label: Text('笔记 4'),
      ),
    ],
  );
}

void _ignoreSelection(bool _) {}

class _NoteDetail extends StatelessWidget {
  const _NoteDetail();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('阅读的技艺', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        Text(
          '真正的阅读是一种主动的工作。',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 20),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.tertiaryContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(color: colors.tertiary, width: 4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '阅读不是被动地接收文字，而是与作者一起组织、检验和重建观点。',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colors.onTertiaryContainer,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('阅读的技艺 · 第二章', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 32),
        Text('我的注释', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(
          '在这里记录你对高亮内容的思考。后续将接入 Markdown 编辑、标签和导出功能。',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }
}

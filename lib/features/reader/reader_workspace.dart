import 'package:flutter/material.dart';

class ReaderWorkspace extends StatelessWidget {
  const ReaderWorkspace({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showPanels = constraints.maxWidth >= 980;
        return Column(
          children: [
            const _ReaderToolbar(),
            Expanded(
              child: Row(
                children: [
                  if (showPanels)
                    const SizedBox(width: 260, child: _ReaderTocPanel()),
                  if (showPanels) const VerticalDivider(width: 1),
                  const Expanded(child: _ReaderArticle()),
                  if (showPanels) const VerticalDivider(width: 1),
                  if (showPanels)
                    const SizedBox(width: 280, child: _ReaderNotesPanel()),
                ],
              ),
            ),
            const _ReaderFooter(),
          ],
        );
      },
    );
  }
}

class _ReaderToolbar extends StatelessWidget {
  const _ReaderToolbar();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            IconButton(
              tooltip: '目录',
              onPressed: () {},
              icon: const Icon(Icons.format_list_bulleted),
            ),
            IconButton(
              tooltip: '笔记',
              onPressed: () {},
              icon: const Icon(Icons.sticky_note_2_outlined),
            ),
            IconButton(
              tooltip: '书签',
              onPressed: () {},
              icon: const Icon(Icons.bookmark_border),
            ),
            const Spacer(),
            const Flexible(
              child: Text('第二章  阅读的层次', overflow: TextOverflow.ellipsis),
            ),
            const Spacer(),
            IconButton(
              tooltip: '字体设置',
              onPressed: () {},
              icon: const Icon(Icons.format_size),
            ),
            IconButton(
              tooltip: '搜索书内内容',
              onPressed: () {},
              icon: const Icon(Icons.search),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderTocPanel extends StatelessWidget {
  const _ReaderTocPanel();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('目录', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        ...const [
          '序言',
          '第一章 阅读的活力与艺术',
          '第二章 阅读的层次',
          '第三章 基础阅读',
          '第四章 检视阅读',
        ].map(
          (chapter) => ListTile(
            contentPadding: EdgeInsets.zero,
            selected: chapter.startsWith('第二章'),
            title: Text(chapter),
          ),
        ),
      ],
    );
  }
}

class _ReaderArticle extends StatelessWidget {
  const _ReaderArticle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(32, 36, 32, 48),
          children: [
            Text('第二章', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Text('阅读的层次', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 28),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 760) {
                  return const _ArticleColumn(paragraphs: _articleText);
                }
                final splitAt = (_articleText.length / 2).ceil();
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _ArticleColumn(
                        paragraphs: _articleText.take(splitAt).toList(),
                      ),
                    ),
                    const SizedBox(width: 48),
                    Expanded(
                      child: _ArticleColumn(
                        paragraphs: _articleText.skip(splitAt).toList(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ArticleColumn extends StatelessWidget {
  const _ArticleColumn({required this.paragraphs});

  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: paragraphs
        .map(
          (paragraph) => Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(
              paragraph,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(height: 1.9),
            ),
          ),
        )
        .toList(),
  );
}

class _ReaderNotesPanel extends StatelessWidget {
  const _ReaderNotesPanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('笔记与标注', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(radius: 8, backgroundColor: Colors.amber),
            title: Text('真正的阅读是一种主动的工作。'),
            subtitle: Text('第二章 · 位置 38%'),
          ),
          const Divider(),
          Text('选中文本后可创建高亮和笔记。', style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ReaderFooter extends StatelessWidget {
  const _ReaderFooter();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Row(
          children: [
            IconButton(
              tooltip: '上一页',
              onPressed: () {},
              icon: const Icon(Icons.chevron_left),
            ),
            const SizedBox(width: 8),
            const Expanded(child: LinearProgressIndicator(value: .38)),
            const SizedBox(width: 12),
            const Text('38% · 16 / 264'),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '下一页',
              onPressed: () {},
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}

const _articleText = [
  '有些人把阅读视为消遣，有些人把它当作获取资讯的手段。但真正的阅读，始终是一种主动的工作。读者并不是被动地接收文字，而是在作者的引导下不断提问、判断与回应。',
  '我们可以把阅读分成不同层次。每一个层次都建立在前一个层次之上，并带来更完整的理解。读得更多并不必然意味着读得更好，关键在于你是否能用恰当的方法，面对眼前这本书。',
  '最基础的阅读，帮助我们辨认文字与理解句子；检视阅读则让我们在有限时间内掌握一本书的轮廓。更进一步的分析阅读，要求读者和作者进行一场耐心而严肃的对话。',
  '当你发现某个观点值得停留，不妨划下一段文字，写下当时的疑问。一本读过、思考过、留下痕迹的书，会逐渐成为你自己的书。',
];

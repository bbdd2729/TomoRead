import 'package:flutter/material.dart';

void main() {
  runApp(const TomoReadApp());
}

class TomoReadApp extends StatelessWidget {
  const TomoReadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TomoRead',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const AppShell(),
    );
  }
}

enum AppDestination { library, chat, notes, skills, statistics }

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _desktopBreakpoint = 840.0;
  AppDestination _destination = AppDestination.library;

  void _selectDestination(AppDestination destination) {
    setState(() => _destination = destination);
    Navigator.maybePop(context);
  }

  void _showImportPlaceholder() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('导入书籍功能将在下一阶段接入。')));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= _desktopBreakpoint;
        final content = _AppContent(
          destination: _destination,
          onImport: _showImportPlaceholder,
        );

        return Scaffold(
          appBar: AppBar(
            title: const Text('TomoRead'),
            actions: [
              IconButton(
                tooltip: '搜索',
                onPressed: () {},
                icon: const Icon(Icons.search),
              ),
              IconButton(
                tooltip: '设置',
                onPressed: () {},
                icon: const Icon(Icons.settings_outlined),
              ),
              const SizedBox(width: 8),
            ],
          ),
          drawer: isDesktop
              ? null
              : _AppNavigationDrawer(
                  selected: _destination,
                  onSelected: _selectDestination,
                ),
          body: isDesktop
              ? Row(
                  children: [
                    _AppNavigationRail(
                      selected: _destination,
                      onSelected: _selectDestination,
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: content),
                  ],
                )
              : content,
        );
      },
    );
  }
}

class _AppNavigationRail extends StatelessWidget {
  const _AppNavigationRail({required this.selected, required this.onSelected});

  final AppDestination selected;
  final ValueChanged<AppDestination> onSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      extended: true,
      minExtendedWidth: 220,
      selectedIndex: selected.index,
      leading: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: FloatingActionButton.small(
          tooltip: '添加书籍',
          onPressed: () {},
          child: const Icon(Icons.add),
        ),
      ),
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.settings_outlined),
            label: const Text('设置'),
          ),
        ),
      ),
      onDestinationSelected: (index) =>
          onSelected(AppDestination.values[index]),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.local_library_outlined),
          selectedIcon: Icon(Icons.local_library),
          label: Text('书库'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.forum_outlined),
          selectedIcon: Icon(Icons.forum),
          label: Text('对话'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.sticky_note_2_outlined),
          selectedIcon: Icon(Icons.sticky_note_2),
          label: Text('笔记'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.extension_outlined),
          selectedIcon: Icon(Icons.extension),
          label: Text('技能'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.bar_chart_outlined),
          selectedIcon: Icon(Icons.bar_chart),
          label: Text('阅读统计'),
        ),
      ],
    );
  }
}

class _AppNavigationDrawer extends StatelessWidget {
  const _AppNavigationDrawer({
    required this.selected,
    required this.onSelected,
  });

  final AppDestination selected;
  final ValueChanged<AppDestination> onSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationDrawer(
      selectedIndex: selected.index,
      onDestinationSelected: (index) =>
          onSelected(AppDestination.values[index]),
      children: const [
        Padding(
          padding: EdgeInsets.fromLTRB(28, 20, 16, 12),
          child: Text(
            'TomoRead',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.local_library_outlined),
          selectedIcon: Icon(Icons.local_library),
          label: Text('书库'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.forum_outlined),
          selectedIcon: Icon(Icons.forum),
          label: Text('对话'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.sticky_note_2_outlined),
          selectedIcon: Icon(Icons.sticky_note_2),
          label: Text('笔记'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.extension_outlined),
          selectedIcon: Icon(Icons.extension),
          label: Text('技能'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.bar_chart_outlined),
          selectedIcon: Icon(Icons.bar_chart),
          label: Text('阅读统计'),
        ),
      ],
    );
  }
}

class _AppContent extends StatelessWidget {
  const _AppContent({required this.destination, required this.onImport});

  final AppDestination destination;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return switch (destination) {
      AppDestination.library => LibraryHomePage(onImport: onImport),
      AppDestination.chat => const _PlaceholderPage(
        title: '对话',
        description: '与书籍内容对话的工作区将在后续接入。',
        icon: Icons.forum_outlined,
      ),
      AppDestination.notes => const _PlaceholderPage(
        title: '笔记',
        description: '高亮、笔记和导出功能将在后续接入。',
        icon: Icons.sticky_note_2_outlined,
      ),
      AppDestination.skills => const _PlaceholderPage(
        title: '技能',
        description: '阅读辅助技能将在后续接入。',
        icon: Icons.extension_outlined,
      ),
      AppDestination.statistics => const _PlaceholderPage(
        title: '阅读统计',
        description: '阅读时长、连续阅读与趋势统计将在后续接入。',
        icon: Icons.bar_chart_outlined,
      ),
    };
  }
}

class LibraryHomePage extends StatelessWidget {
  const LibraryHomePage({super.key, required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _PageHeader(onImport: onImport),
        const SizedBox(height: 24),
        const _ContinueReadingCard(),
        const SizedBox(height: 32),
        Text('全部书籍', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 190,
            mainAxisExtent: 270,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
          ),
          itemCount: _sampleBooks.length,
          itemBuilder: (context, index) => _BookCard(book: _sampleBooks[index]),
        ),
      ],
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 16,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('书库', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 6),
            Text('管理并继续阅读你的书籍。', style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
        FilledButton.icon(
          onPressed: onImport,
          icon: const Icon(Icons.add),
          label: const Text('导入书籍'),
        ),
      ],
    );
  }
}

class _ContinueReadingCard extends StatelessWidget {
  const _ContinueReadingCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const _BookCover(icon: Icons.auto_stories, color: Colors.indigo),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('继续阅读', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Text('阅读的技艺', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  const Text('第二章  阅读的层次'),
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(value: .38),
                  const SizedBox(height: 8),
                  Text('已读 38%', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 16),
            IconButton.filledTonal(
              tooltip: '继续阅读',
              onPressed: () {},
              icon: const Icon(Icons.play_arrow),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({required this.book});

  final _BookSummary book;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _BookCover(icon: book.icon, color: book.color),
              ),
              const SizedBox(height: 12),
              Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                book.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(value: book.progress),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(book.progress * 100).round()}%',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color.withValues(alpha: .16)),
      child: Center(child: Icon(icon, size: 44, color: color)),
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(description, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookSummary {
  const _BookSummary({
    required this.title,
    required this.author,
    required this.progress,
    required this.icon,
    required this.color,
  });

  final String title;
  final String author;
  final double progress;
  final IconData icon;
  final Color color;
}

const _sampleBooks = [
  _BookSummary(
    title: '阅读的技艺',
    author: '莫提默·J. 艾德勒',
    progress: .38,
    icon: Icons.auto_stories,
    color: Colors.indigo,
  ),
  _BookSummary(
    title: '思考，快与慢',
    author: '丹尼尔·卡尼曼',
    progress: .16,
    icon: Icons.psychology,
    color: Colors.deepOrange,
  ),
  _BookSummary(
    title: '月亮与六便士',
    author: '毛姆',
    progress: .72,
    icon: Icons.nightlight_round,
    color: Colors.teal,
  ),
  _BookSummary(
    title: '人类简史',
    author: '尤瓦尔·赫拉利',
    progress: .05,
    icon: Icons.public,
    color: Colors.brown,
  ),
  _BookSummary(
    title: '置身事内',
    author: '兰小欢',
    progress: .48,
    icon: Icons.account_balance,
    color: Colors.blue,
  ),
  _BookSummary(
    title: '纳瓦尔宝典',
    author: '埃里克·乔根森',
    progress: .92,
    icon: Icons.diamond_outlined,
    color: Colors.purple,
  ),
];

import 'package:flutter/material.dart';

class NotesPage extends StatelessWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 300,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('笔记本', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              const ListTile(
                leading: Icon(Icons.highlight_alt),
                title: Text('高亮'),
                trailing: Text('12'),
              ),
              const ListTile(
                leading: Icon(Icons.sticky_note_2_outlined),
                title: Text('笔记'),
                trailing: Text('4'),
              ),
              const Divider(),
              const ListTile(
                title: Text('真正的阅读是一种主动的工作。'),
                subtitle: Text('阅读的技艺 · 第二章'),
                selected: true,
              ),
              const ListTile(
                title: Text('检视阅读帮助我们掌握轮廓。'),
                subtitle: Text('阅读的技艺 · 第四章'),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '真正的阅读是一种主动的工作。',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Chip(label: Text('阅读的技艺 · 第二章')),
                const SizedBox(height: 24),
                const Text('在这里记录你对高亮内容的思考。后续将接入 Markdown 编辑、标签和导出功能。'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

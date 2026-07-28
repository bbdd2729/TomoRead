import 'package:flutter/material.dart';

import '../../shared/widgets/page_header.dart';

class SkillsPage extends StatelessWidget {
  const SkillsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const PageHeader(title: '技能', subtitle: '为阅读流程添加可复用的辅助能力。'),
        const SizedBox(height: 24),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.35,
          children: const [
            _SkillCard(
              icon: Icons.summarize_outlined,
              title: '章节总结',
              description: '提取本章的要点和问题。',
            ),
            _SkillCard(
              icon: Icons.lightbulb_outline,
              title: '概念解释',
              description: '解释选中的概念与术语。',
            ),
            _SkillCard(
              icon: Icons.account_tree_outlined,
              title: '结构梳理',
              description: '整理书籍的章节结构。',
            ),
          ],
        ),
      ],
    );
  }
}

class _SkillCard extends StatelessWidget {
  const _SkillCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const Spacer(),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

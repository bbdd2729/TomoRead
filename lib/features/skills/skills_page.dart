import 'package:flutter/material.dart';

import '../../shared/widgets/page_header.dart';

class SkillsPage extends StatelessWidget {
  const SkillsPage({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final horizontalPadding = constraints.maxWidth < 600 ? 20.0 : 32.0;
      return ListView(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          28,
          horizontalPadding,
          48,
        ),
        children: [
          const PageHeader(title: '技能', subtitle: '为阅读流程添加可复用的辅助能力。'),
          const SizedBox(height: 28),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _skills.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 300,
              mainAxisExtent: 176,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
            ),
            itemBuilder: (context, index) => _SkillCard(
              icon: _skills[index].icon,
              title: _skills[index].title,
              description: _skills[index].description,
            ),
          ),
        ],
      );
    },
  );
}

const _skills = [
  (icon: Icons.summarize_outlined, title: '章节总结', description: '提取本章的要点和问题。'),
  (icon: Icons.lightbulb_outline, title: '概念解释', description: '解释选中的概念与术语。'),
  (icon: Icons.account_tree_outlined, title: '结构梳理', description: '整理书籍的章节结构。'),
];

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
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(icon, color: colors.onSecondaryContainer),
                ),
              ),
              const Spacer(),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

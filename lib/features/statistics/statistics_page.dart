import 'package:flutter/material.dart';

import '../../shared/widgets/page_header.dart';

class StatisticsPage extends StatelessWidget {
  const StatisticsPage({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 600;
      final horizontalPadding = compact ? 20.0 : 32.0;
      return ListView(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          28,
          horizontalPadding,
          48,
        ),
        children: [
          const PageHeader(title: '阅读统计', subtitle: '追踪你的阅读习惯和进度。'),
          const SizedBox(height: 28),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _statistics.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 244,
              mainAxisExtent: 148,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            itemBuilder: (context, index) => _StatisticCard(
              label: _statistics[index].label,
              value: _statistics[index].value,
              icon: _statistics[index].icon,
            ),
          ),
          const SizedBox(height: 36),
          Text('近 30 天趋势', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('每天的阅读时长变化。', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Card(
            child: SizedBox(
              height: compact ? 208 : 252,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 24, 16),
                child: CustomPaint(
                  painter: _TrendPainter(
                    lineColor: Theme.of(context).colorScheme.primary,
                    gridColor: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 36),
          Text('阅读活动', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('过去 12 周的阅读记录。', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(
                  84,
                  (index) => _ActivityCell(active: index % 11 == 0),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

const _statistics = [
  (label: '已读书籍', value: '6', icon: Icons.menu_book_outlined),
  (label: '阅读时长', value: '12h 40m', icon: Icons.timer_outlined),
  (label: '当前连续', value: '4 天', icon: Icons.local_fire_department_outlined),
  (label: '日均时长', value: '24m', icon: Icons.trending_up),
];

class _StatisticCard extends StatelessWidget {
  const _StatisticCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(icon, color: colors.onSecondaryContainer, size: 20),
              ),
            ),
            const Spacer(),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ActivityCell extends StatelessWidget {
  const _ActivityCell({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: active ? '完成阅读' : '暂无记录',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: active
              ? colors.primaryContainer
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(3),
        ),
        child: const SizedBox(width: 16, height: 16),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({required this.lineColor, required this.gridColor});

  final Color lineColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var row = 1; row < 4; row++) {
      final y = size.height * row / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final path = Path()
      ..moveTo(0, size.height * .82)
      ..cubicTo(
        size.width * .16,
        size.height * .82,
        size.width * .18,
        size.height * .46,
        size.width * .32,
        size.height * .58,
      )
      ..cubicTo(
        size.width * .5,
        size.height * .75,
        size.width * .6,
        size.height * .2,
        size.width * .74,
        size.height * .38,
      )
      ..cubicTo(
        size.width * .85,
        size.height * .5,
        size.width * .88,
        size.height * .14,
        size.width,
        size.height * .24,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      oldDelegate.lineColor != lineColor || oldDelegate.gridColor != gridColor;
}

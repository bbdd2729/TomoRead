import 'package:flutter/material.dart';

import '../../shared/widgets/page_header.dart';

class StatisticsPage extends StatelessWidget {
  const StatisticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const PageHeader(title: '阅读统计', subtitle: '追踪你的阅读习惯和进度。'),
        const SizedBox(height: 24),
        const Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _StatisticCard(
              label: '已读书籍',
              value: '6',
              icon: Icons.menu_book_outlined,
            ),
            _StatisticCard(
              label: '阅读时长',
              value: '12h 40m',
              icon: Icons.timer_outlined,
            ),
            _StatisticCard(
              label: '当前连续',
              value: '4 天',
              icon: Icons.local_fire_department_outlined,
            ),
            _StatisticCard(
              label: '日均时长',
              value: '24m',
              icon: Icons.trending_up,
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text('近 30 天趋势', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Card(
          child: SizedBox(
            height: 240,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: CustomPaint(
                painter: _TrendPainter(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text('阅读活动', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(
                84,
                (index) => Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: index % 11 == 0
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

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
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 20),
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = color.withValues(alpha: .2)
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
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) => oldDelegate.color != color;
}

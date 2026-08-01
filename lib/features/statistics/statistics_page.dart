import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../domain/models/library_book.dart';
import '../../domain/models/stats_models.dart';
import '../../shared/widgets/page_header.dart';
import 'statistics_providers.dart';

class StatisticsPage extends ConsumerWidget {
  const StatisticsPage({super.key, this.onOpenReader});

  final ValueChanged<LibraryBook>? onOpenReader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(statisticsSelectionProvider);
    final viewModel = ref.watch(statsViewModelProvider);
    return viewModel.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _StatisticsError(
        error: error,
        onRetry: () => ref.invalidate(statsReportProvider),
      ),
      data: (model) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final padding = compact ? 20.0 : 32.0;
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(padding, 28, padding, 18),
                sliver: SliverToBoxAdapter(
                  child: PageHeader(
                    title: '阅读统计',
                    subtitle: '只统计前台、可见并发生阅读交互的有效时间',
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: padding),
                sliver: SliverToBoxAdapter(
                  child: _PeriodToolbar(
                    selection: selection,
                    report: model.report,
                    onDimensionChanged: (value) => ref
                        .read(statisticsSelectionProvider.notifier)
                        .setDimension(value),
                    onPrevious: () =>
                        ref.read(statisticsSelectionProvider.notifier).move(-1),
                    onNext: model.report.canGoNext
                        ? () => ref
                              .read(statisticsSelectionProvider.notifier)
                              .move(1)
                        : null,
                  ),
                ),
              ),
              if (model.report.summary.activeMillis == 0)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyStatistics(
                    periodLabel: model.report.period.label,
                  ),
                )
              else ...[
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(padding, 22, padding, 0),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) =>
                          _MetricTile(metric: model.metrics[index]),
                      childCount: model.metrics.length,
                    ),
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: compact ? 220 : 260,
                      mainAxisExtent: 122,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(padding, 34, padding, 0),
                  sliver: SliverToBoxAdapter(
                    child: _ActivitySection(
                      timeline: model.report.timeline,
                      periodLabel: model.report.period.label,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(padding, 34, padding, 48),
                  sliver: SliverToBoxAdapter(
                    child: _TopBooksSection(
                      entries: model.report.topBooks,
                      onOpenReader: onOpenReader,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PeriodToolbar extends StatelessWidget {
  const _PeriodToolbar({
    required this.selection,
    required this.report,
    required this.onDimensionChanged,
    required this.onPrevious,
    required this.onNext,
  });

  final StatsSelection selection;
  final StatsReport report;
  final ValueChanged<StatsDimension> onDimensionChanged;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 650;
      final dimensions = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<StatsDimension>(
          segments: const [
            ButtonSegment(value: StatsDimension.day, label: Text('日')),
            ButtonSegment(value: StatsDimension.week, label: Text('周')),
            ButtonSegment(value: StatsDimension.month, label: Text('月')),
            ButtonSegment(value: StatsDimension.year, label: Text('年')),
            ButtonSegment(value: StatsDimension.lifetime, label: Text('全部')),
          ],
          selected: {selection.dimension},
          onSelectionChanged: (value) => onDimensionChanged(value.first),
        ),
      );
      final navigation = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '上一个周期',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 150),
            child: Text(report.period.label, textAlign: TextAlign.center),
          ),
          IconButton(
            tooltip: '下一个周期',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      );
      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [dimensions, const SizedBox(height: 12), navigation],
        );
      }
      return Row(
        children: [
          Expanded(child: dimensions),
          navigation,
        ],
      );
    },
  );
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});

  final StatsMetricViewModel metric;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final icon = switch (metric.icon) {
      'calendar' => Icons.calendar_today_outlined,
      'streak' => Icons.local_fire_department_outlined,
      'books' => Icons.menu_book_outlined,
      _ => Icons.schedule,
    };
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SizedBox(
                width: 42,
                height: 42,
                child: Icon(icon, size: 21),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    metric.value,
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    metric.label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({required this.timeline, required this.periodLabel});

  final List<ActivityPoint> timeline;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final totalMinutes = timeline.fold<int>(
      0,
      (sum, point) => sum + (point.activeMillis / 60000).round(),
    );
    final chartWidth = math.max(640.0, timeline.length * 36.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('阅读趋势', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          '$periodLabel 共阅读 $totalMinutes 分钟',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 260,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Semantics(
                label: '$periodLabel 阅读趋势，总计 $totalMinutes 分钟',
                child: SizedBox(
                  width: chartWidth,
                  child: CustomPaint(
                    painter: _ActivityChartPainter(
                      points: timeline,
                      barColor: Theme.of(context).colorScheme.primary,
                      gridColor: Theme.of(context).colorScheme.outlineVariant,
                      labelStyle:
                          Theme.of(context).textTheme.labelSmall ??
                          const TextStyle(fontSize: 11),
                    ),
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

class _ActivityChartPainter extends CustomPainter {
  const _ActivityChartPainter({
    required this.points,
    required this.barColor,
    required this.gridColor,
    required this.labelStyle,
  });

  final List<ActivityPoint> points;
  final Color barColor;
  final Color gridColor;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const labelHeight = 28.0;
    final chartHeight = size.height - labelHeight;
    final maxValue = points
        .map((point) => point.activeMillis)
        .fold<int>(1, math.max);
    final slot = size.width / points.length;
    final barWidth = math.min(18.0, slot * .58);
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var index = 0; index <= 4; index++) {
      final y = chartHeight * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final paint = Paint()..color = barColor;
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final height = chartHeight * point.activeMillis / maxValue;
      final left = slot * index + (slot - barWidth) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, chartHeight - height, barWidth, height),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, paint);
      final label = TextPainter(
        text: TextSpan(text: point.label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: slot);
      label.paint(
        canvas,
        Offset(slot * index + (slot - label.width) / 2, chartHeight + 8),
      );
    }
  }

  @override
  bool shouldRepaint(_ActivityChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.barColor != barColor ||
      oldDelegate.gridColor != gridColor;
}

class _TopBooksSection extends StatelessWidget {
  const _TopBooksSection({required this.entries, required this.onOpenReader});

  final List<TopBookEntry> entries;
  final ValueChanged<LibraryBook>? onOpenReader;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('阅读最多', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        ...entries.asMap().entries.map((entry) {
          final item = entry.value;
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  child: Text('${entry.key + 1}', textAlign: TextAlign.center),
                ),
                const SizedBox(width: 10),
                _BookCover(book: item.book),
              ],
            ),
            title: Text(item.book.title),
            subtitle: Text(
              item.book.author.isEmpty ? '未知作者' : item.book.author,
            ),
            trailing: Text(formatReadingDuration(item.activeMillis)),
            onTap: onOpenReader == null ? null : () => onOpenReader!(item.book),
          );
        }),
      ],
    );
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.book});

  final LibraryBook book;

  @override
  Widget build(BuildContext context) {
    final path = book.coverPath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 38,
        height: 52,
        child: path != null && File(path).existsSync()
            ? Image.file(File(path), fit: BoxFit.cover, cacheWidth: 96)
            : ColoredBox(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: const Icon(Icons.menu_book_outlined, size: 20),
              ),
      ),
    );
  }
}

class _EmptyStatistics extends StatelessWidget {
  const _EmptyStatistics({required this.periodLabel});

  final String periodLabel;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insights_outlined, size: 48),
          const SizedBox(height: 14),
          Text(
            '$periodLabel 还没有阅读记录',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text('打开一本书并开始阅读后，这里会记录有效阅读时间。', textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _StatisticsError extends StatelessWidget {
  const _StatisticsError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('无法加载阅读统计：$error'),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('重试'),
        ),
      ],
    ),
  );
}

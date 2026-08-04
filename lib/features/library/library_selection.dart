import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

class LibrarySelectionToolbar extends StatelessWidget {
  const LibrarySelectionToolbar({
    required this.selectedCount,
    required this.isWorking,
    required this.allSelectedAreFavorite,
    required this.onCancel,
    required this.onToggleFavorite,
    required this.onChangeCategory,
    required this.onDelete,
  });

  final int selectedCount;
  final bool isWorking;
  final bool allSelectedAreFavorite;
  final VoidCallback onCancel;
  final VoidCallback onToggleFavorite;
  final VoidCallback onChangeCategory;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('library-selection-toolbar'),
    color: Theme.of(context).colorScheme.secondaryContainer,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            tooltip: '退出多选',
            onPressed: isWorking ? null : onCancel,
            icon: const Icon(Icons.close),
          ),
          Expanded(child: Text('已选择 $selectedCount 本书')),
          IconButton(
            tooltip: allSelectedAreFavorite ? '取消收藏' : '收藏书籍',
            onPressed: isWorking || selectedCount == 0
                ? null
                : onToggleFavorite,
            icon: Icon(
              allSelectedAreFavorite ? Icons.favorite : Icons.favorite_border,
            ),
          ),
          IconButton(
            tooltip: '设置分类',
            onPressed: isWorking || selectedCount == 0
                ? null
                : onChangeCategory,
            icon: const Icon(Icons.folder_outlined),
          ),
          IconButton(
            tooltip: '删除书籍',
            onPressed: isWorking || selectedCount == 0 ? null : onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    ),
  );
}

class CategoryUpdate {
  const CategoryUpdate(this.category);

  final String? category;
}

class CategoryDialog extends HookWidget {
  const CategoryDialog({required this.categories});

  final List<String> categories;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController();
    return AlertDialog(
      title: const Text('设置分类'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '分类名称',
                border: OutlineInputBorder(),
              ),
            ),
            if (categories.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in categories)
                    ActionChip(
                      label: Text(category),
                      onPressed: () => controller.text = category,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, const CategoryUpdate(null)),
          child: const Text('清除分类'),
        ),
        FilledButton(
          onPressed: () {
            final category = controller.text.trim();
            if (category.isEmpty) return;
            Navigator.pop(context, CategoryUpdate(category));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

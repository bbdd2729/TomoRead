import 'package:flutter/material.dart';

import '../../domain/models/bookmark.dart';

class PdfBookmarksDialog extends StatelessWidget {
  const PdfBookmarksDialog({super.key, required this.bookmarks});

  final List<Bookmark> bookmarks;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('PDF 书签'),
      content: SizedBox(
        width: 440,
        height: 420,
        child: bookmarks.isEmpty
            ? const Center(child: Text('当前 PDF 还没有书签。'))
            : ListView.separated(
                itemCount: bookmarks.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final bookmark = bookmarks[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bookmark),
                    title: Text(bookmark.label ?? bookmark.chapterTitle),
                    subtitle: Text(
                      '保存于 ${bookmark.createdAt.hour.toString().padLeft(2, '0')}:${bookmark.createdAt.minute.toString().padLeft(2, '0')}',
                    ),
                    onTap: () => Navigator.pop(context, bookmark),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

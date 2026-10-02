import 'package:flutter/material.dart';

import '../../domain/models/bookmark.dart';

class PdfBookmarksDialog extends StatelessWidget {
  const PdfBookmarksDialog({super.key, required this.bookmarks});

  final List<Bookmark> bookmarks;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إشارات مرجعية PDF'),
      content: SizedBox(
        width: 440,
        height: 420,
        child: bookmarks.isEmpty
            ? const Center(child: Text('لا توجد إشارات مرجعية لملف PDF الحالي.'))
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
                      'تم الحفظ في${bookmark.createdAt.hour.toString().padLeft(2, '0')}:${bookmark.createdAt.minute.toString().padLeft(2, '0')}',
                    ),
                    onTap: () => Navigator.pop(context, bookmark),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('مغلق'),
        ),
      ],
    );
  }
}

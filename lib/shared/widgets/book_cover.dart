import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/models/library_book.dart';

class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book});

  final LibraryBook book;

  @override
  Widget build(BuildContext context) {
    final coverPath = book.coverPath;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (coverPath == null) return _fallback(context);

        final logicalHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 240.0;
        final cacheHeight =
            (logicalHeight * MediaQuery.devicePixelRatioOf(context))
                .round()
                .clamp(256, 1200);
        return Image.file(
          File(coverPath),
          cacheHeight: cacheHeight,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _fallback(context),
        );
      },
    );
  }

  Widget _fallback(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
    ),
    child: Center(
      child: Icon(
        book.format == 'pdf'
            ? Icons.picture_as_pdf_outlined
            : Icons.menu_book_outlined,
        size: 44,
      ),
    ),
  );
}

String bookCoverHeroTag(LibraryBook book) => 'book-cover-${book.id}';

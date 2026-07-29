import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/models/library_book.dart';

class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book});

  final LibraryBook book;

  @override
  Widget build(BuildContext context) {
    final coverPath = book.coverPath;
    if (coverPath != null && File(coverPath).existsSync()) {
      return Image.file(
        File(coverPath),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(context),
      );
    }
    return _fallback(context);
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

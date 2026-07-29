import 'package:flutter/material.dart';

import '../../domain/models/library_book.dart';

class BookSearchDelegate extends SearchDelegate<LibraryBook?> {
  BookSearchDelegate(this.books) : super(searchFieldLabel: '搜索书籍');

  final List<LibraryBook> books;

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: '清除搜索',
        onPressed: () => query = '',
        icon: const Icon(Icons.clear),
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    tooltip: '关闭搜索',
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back),
  );

  @override
  Widget buildResults(BuildContext context) => _BookSearchResults(
    books: _matchingBooks,
    onSelected: (book) => close(context, book),
  );

  @override
  Widget buildSuggestions(BuildContext context) => _BookSearchResults(
    books: _matchingBooks,
    onSelected: (book) => close(context, book),
  );

  List<LibraryBook> get _matchingBooks {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return books;
    return books
        .where(
          (book) => '${book.title} ${book.author}'.toLowerCase().contains(
            normalizedQuery,
          ),
        )
        .toList();
  }
}

class _BookSearchResults extends StatelessWidget {
  const _BookSearchResults({required this.books, required this.onSelected});

  final List<LibraryBook> books;
  final ValueChanged<LibraryBook> onSelected;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return const Center(child: Text('没有匹配的书籍'));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: books.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final book = books[index];
        return ListTile(
          leading: Icon(
            book.format == 'pdf'
                ? Icons.picture_as_pdf_outlined
                : Icons.menu_book_outlined,
          ),
          title: Text(book.title),
          subtitle: Text(
            book.author.isEmpty
                ? book.format.toUpperCase()
                : '${book.author} · ${book.format.toUpperCase()}',
          ),
          trailing: Text('${(book.progress * 100).round()}%'),
          onTap: () => onSelected(book),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

enum ImportSourceChoice { files, directory }

class ImportSourceDialog extends StatelessWidget {
  const ImportSourceDialog({super.key});

  @override
  Widget build(BuildContext context) => SimpleDialog(
    title: const Text('تحديد مصدر الاستيراد'),
    children: [
      SimpleDialogOption(
        onPressed: () => Navigator.of(context).pop(ImportSourceChoice.files),
        child: const ListTile(
          leading: Icon(Icons.file_open_outlined),
          title: Text('اختر ملفا…'),
          subtitle: Text('حدد عدة ملفات EPUB أو PDF أو TXT أو Markdown في وقت واحد'),
        ),
      ),
      SimpleDialogOption(
        onPressed: () =>
            Navigator.of(context).pop(ImportSourceChoice.directory),
        child: const ListTile(
          leading: Icon(Icons.folder_open_outlined),
          title: Text('افحص المجلّد'),
          subtitle: Text('معاينة الملفات المدعومة بشكل متكرر وتأكيدها واستيرادها'),
        ),
      ),
    ],
  );
}

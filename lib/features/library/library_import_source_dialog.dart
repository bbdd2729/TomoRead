import 'package:flutter/material.dart';

enum ImportSourceChoice { files, directory }

class ImportSourceDialog extends StatelessWidget {
  const ImportSourceDialog({super.key});

  @override
  Widget build(BuildContext context) => SimpleDialog(
    title: const Text('选择导入来源'),
    children: [
      SimpleDialogOption(
        onPressed: () => Navigator.of(context).pop(ImportSourceChoice.files),
        child: const ListTile(
          leading: Icon(Icons.file_open_outlined),
          title: Text('选择文件'),
          subtitle: Text('一次选择多个 EPUB、PDF、TXT 或 Markdown 文件'),
        ),
      ),
      SimpleDialogOption(
        onPressed: () =>
            Navigator.of(context).pop(ImportSourceChoice.directory),
        child: const ListTile(
          leading: Icon(Icons.folder_open_outlined),
          title: Text('扫描文件夹'),
          subtitle: Text('递归预览支持的文件，确认后再导入'),
        ),
      ),
    ],
  );
}

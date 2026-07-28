import 'package:flutter/material.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 260,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.add),
                  label: const Text('新建对话'),
                ),
                const SizedBox(height: 16),
                const ListTile(
                  leading: Icon(Icons.chat_bubble_outline),
                  title: Text('关于阅读的几个问题'),
                  selected: true,
                ),
                const ListTile(
                  leading: Icon(Icons.chat_bubble_outline),
                  title: Text('本周阅读计划'),
                ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '关于阅读的几个问题',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: _ChatMessages(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: TextField(
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: '输入你想讨论的内容',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.send),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatMessages extends StatelessWidget {
  const _ChatMessages();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        Align(
          alignment: Alignment.centerRight,
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('这本书的核心观点是什么？'),
            ),
          ),
        ),
        SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('这里会展示基于当前书籍内容生成的回答，并附带可跳转的出处。'),
            ),
          ),
        ),
      ],
    );
  }
}

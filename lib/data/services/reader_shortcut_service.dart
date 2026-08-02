import '../../domain/models/reader_commands.dart';

class ReaderShortcutValidationIssue {
  const ReaderShortcutValidationIssue({
    required this.message,
    this.command,
    this.conflictingCommand,
  });

  final String message;
  final ReaderCommand? command;
  final ReaderCommand? conflictingCommand;
}

class ReaderShortcutValidationResult {
  const ReaderShortcutValidationResult(this.issues);

  final List<ReaderShortcutValidationIssue> issues;

  bool get isValid => issues.isEmpty;
}

class ReaderShortcutService {
  const ReaderShortcutService();

  ReaderShortcutValidationResult validate(ReaderCommandSettings settings) {
    final issues = <ReaderShortcutValidationIssue>[];
    final identities = <String>{};
    final activeChords = <String, ReaderShortcutBinding>{};
    for (final binding in settings.bindings) {
      final identity = '${binding.platform.name}:${binding.command.name}';
      if (!identities.add(identity)) {
        issues.add(
          ReaderShortcutValidationIssue(
            command: binding.command,
            message: '${binding.command.label}存在重复的平台绑定。',
          ),
        );
        continue;
      }
      if (!binding.enabled) continue;
      final chord = binding.chord;
      if (chord == null) {
        issues.add(
          ReaderShortcutValidationIssue(
            command: binding.command,
            message: '${binding.command.label}已启用，但没有设置快捷键。',
          ),
        );
        continue;
      }
      if (!supportedReaderShortcutKeys.contains(chord.key)) {
        issues.add(
          ReaderShortcutValidationIssue(
            command: binding.command,
            message: '${binding.command.label}使用了不支持的按键。',
          ),
        );
        continue;
      }
      if (_isReserved(binding.platform, chord)) {
        issues.add(
          ReaderShortcutValidationIssue(
            command: binding.command,
            message: '${chord.label} 是系统保留快捷键，不能保存。',
          ),
        );
        continue;
      }
      if (_requiresModifier(chord.key) &&
          !chord.control &&
          !chord.alt &&
          !chord.meta) {
        issues.add(
          ReaderShortcutValidationIssue(
            command: binding.command,
            message: '${chord.label} 会影响文字输入，请至少添加 Ctrl、Alt 或 Meta。',
          ),
        );
        continue;
      }
      final chordIdentity = '${binding.platform.name}:${chord.signature}';
      final conflict = activeChords[chordIdentity];
      if (conflict != null) {
        issues.add(
          ReaderShortcutValidationIssue(
            command: binding.command,
            conflictingCommand: conflict.command,
            message:
                '${binding.command.label}与${conflict.command.label}都使用 ${chord.label}。',
          ),
        );
      } else {
        activeChords[chordIdentity] = binding;
      }
    }

    final expectedCount =
        ReaderCommand.values.length * ReaderShortcutPlatform.values.length;
    if (identities.length != expectedCount) {
      issues.add(
        const ReaderShortcutValidationIssue(message: '快捷键配置缺少命令或平台绑定。'),
      );
    }
    return ReaderShortcutValidationResult(List.unmodifiable(issues));
  }

  bool _requiresModifier(String key) => key.startsWith('key');

  bool _isReserved(
    ReaderShortcutPlatform platform,
    ReaderShortcutChord chord,
  ) {
    final signature = chord.signature;
    return switch (platform) {
      ReaderShortcutPlatform.windows => const {
        'alt+f4',
        'control+alt+delete',
        'meta+keyl',
        'meta+keyd',
      }.contains(signature),
      ReaderShortcutPlatform.linux => const {
        'alt+f4',
        'control+alt+delete',
        'control+alt+keyt',
        'meta+keyl',
      }.contains(signature),
    };
  }
}

class ReaderShortcutException implements Exception {
  const ReaderShortcutException(this.message);

  final String message;

  @override
  String toString() => message;
}

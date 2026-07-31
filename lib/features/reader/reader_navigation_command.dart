enum ReaderNavigationKind { goToLocation, nextPage, previousPage }

class ReaderNavigationCommand {
  const ReaderNavigationCommand._({
    required this.id,
    required this.kind,
    this.href,
    this.ratio,
    this.anchor,
    this.cfi,
  });

  factory ReaderNavigationCommand.goToLocation({
    required int id,
    required String href,
    required double ratio,
    String? anchor,
    String? cfi,
  }) => ReaderNavigationCommand._(
    id: id,
    kind: ReaderNavigationKind.goToLocation,
    href: href,
    ratio: ratio.clamp(0, 1).toDouble(),
    anchor: anchor,
    cfi: cfi,
  );

  const ReaderNavigationCommand.nextPage({required int id})
    : this._(id: id, kind: ReaderNavigationKind.nextPage);

  const ReaderNavigationCommand.previousPage({required int id})
    : this._(id: id, kind: ReaderNavigationKind.previousPage);

  final int id;
  final ReaderNavigationKind kind;
  final String? href;
  final double? ratio;
  final String? anchor;
  final String? cfi;
}

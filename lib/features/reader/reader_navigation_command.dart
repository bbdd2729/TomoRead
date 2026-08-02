enum ReaderNavigationKind {
  goToLocation,
  nextPage,
  previousPage,
  scrollBy,
  startAutoScroll,
  stopAutoScroll,
}

class ReaderNavigationCommand {
  const ReaderNavigationCommand._({
    required this.id,
    required this.kind,
    this.href,
    this.ratio,
    this.anchor,
    this.cfi,
    this.amount,
    this.unit,
    this.speed,
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

  const ReaderNavigationCommand.scrollBy({
    required int id,
    required double amount,
  }) : this._(
         id: id,
         kind: ReaderNavigationKind.scrollBy,
         amount: amount,
       );

  const ReaderNavigationCommand.startAutoScroll({
    required int id,
    required String unit,
    required double speed,
  }) : this._(
         id: id,
         kind: ReaderNavigationKind.startAutoScroll,
         unit: unit,
         speed: speed,
       );

  const ReaderNavigationCommand.stopAutoScroll({required int id})
    : this._(id: id, kind: ReaderNavigationKind.stopAutoScroll);

  final int id;
  final ReaderNavigationKind kind;
  final String? href;
  final double? ratio;
  final String? anchor;
  final String? cfi;
  final double? amount;
  final String? unit;
  final double? speed;
}

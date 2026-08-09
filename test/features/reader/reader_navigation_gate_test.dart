import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/features/reader/reader_navigation_command.dart';

void main() {
  test('allows one navigation command until it completes', () {
    final gate = ReaderNavigationGate();

    expect(gate.tryStart(41), isTrue);
    expect(gate.tryStart(42), isFalse);
    gate.complete(41);
    expect(gate.tryStart(42), isTrue);
  });
}

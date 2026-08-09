import 'package:flutter_test/flutter_test.dart';
import 'package:tomoread/domain/models/reading_settings.dart';

void main() {
  test('defaults volume-key page turning to disabled and copies the setting', () {
    const settings = ReadingSettings();

    expect(settings.volumeKeyTurnsPage, isFalse);
    expect(
      settings.copyWith(volumeKeyTurnsPage: true).volumeKeyTurnsPage,
      isTrue,
    );
  });
}

enum TtsPlaybackStatus { idle, loading, playing, paused, completed, failed }

enum TtsPlaybackEventType {
  segmentStarted,
  wordProgress,
  segmentCompleted,
  completed,
  cancelled,
  failed,
}

class TtsVoice {
  const TtsVoice({required this.id, required this.name, required this.locale});

  final String id;
  final String name;
  final String locale;
}

class TtsSegment {
  const TtsSegment({
    required this.id,
    required this.text,
    required this.href,
    required this.locatorStart,
    required this.locatorEnd,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.rawStart,
    required this.rawEnd,
  });

  final String id;
  final String text;
  final String href;
  final String locatorStart;
  final String locatorEnd;
  final int chapterIndex;
  final String chapterTitle;
  final int rawStart;
  final int rawEnd;
}

class TtsRequest {
  const TtsRequest({
    required this.bookId,
    required this.segments,
    required this.startIndex,
    required this.language,
    required this.rate,
    required this.volume,
    this.voice,
  });

  final String bookId;
  final List<TtsSegment> segments;
  final int startIndex;
  final String language;
  final TtsVoice? voice;
  final double rate;
  final double volume;
}

class TtsPlaybackEvent {
  const TtsPlaybackEvent({
    required this.type,
    this.segmentIndex,
    this.wordStart,
    this.wordEnd,
    this.error,
  });

  final TtsPlaybackEventType type;
  final int? segmentIndex;
  final int? wordStart;
  final int? wordEnd;
  final String? error;
}

class TtsAvailability {
  const TtsAvailability({required this.available, this.reason});

  const TtsAvailability.available() : available = true, reason = null;

  final bool available;
  final String? reason;
}

class TtsSettings {
  const TtsSettings({
    this.rate = .5,
    this.volume = 1,
    this.language = 'zh-CN',
    this.voiceId,
    this.keepAwake = false,
  });

  final double rate;
  final double volume;
  final String language;
  final String? voiceId;
  final bool keepAwake;

  TtsSettings copyWith({
    double? rate,
    double? volume,
    String? language,
    String? voiceId,
    bool? keepAwake,
    bool clearVoice = false,
  }) => TtsSettings(
    rate: rate ?? this.rate,
    volume: volume ?? this.volume,
    language: language ?? this.language,
    voiceId: clearVoice ? null : voiceId ?? this.voiceId,
    keepAwake: keepAwake ?? this.keepAwake,
  );
}

class TtsCursor {
  const TtsCursor({
    required this.bookId,
    required this.segmentId,
    required this.locator,
    required this.chapterIndex,
    required this.updatedAt,
  });

  final String bookId;
  final String segmentId;
  final String locator;
  final int chapterIndex;
  final DateTime updatedAt;
}

class TtsPlaybackState {
  const TtsPlaybackState({
    this.status = TtsPlaybackStatus.idle,
    this.availability = const TtsAvailability(available: false),
    this.settings = const TtsSettings(),
    this.voices = const [],
    this.segments = const [],
    this.currentIndex = 0,
    this.wordStart,
    this.wordEnd,
    this.error,
  });

  final TtsPlaybackStatus status;
  final TtsAvailability availability;
  final TtsSettings settings;
  final List<TtsVoice> voices;
  final List<TtsSegment> segments;
  final int currentIndex;
  final int? wordStart;
  final int? wordEnd;
  final String? error;

  bool get canPlay => availability.available && segments.isNotEmpty;
  TtsSegment? get currentSegment => segments.isEmpty
      ? null
      : segments[currentIndex.clamp(0, segments.length - 1).toInt()];

  TtsVoice? get selectedVoice => voices
      .where((voice) => voice.id == settings.voiceId)
      .firstOrNull;

  TtsPlaybackState copyWith({
    TtsPlaybackStatus? status,
    TtsAvailability? availability,
    TtsSettings? settings,
    List<TtsVoice>? voices,
    List<TtsSegment>? segments,
    int? currentIndex,
    int? wordStart,
    int? wordEnd,
    String? error,
    bool clearWordRange = false,
    bool clearError = false,
  }) => TtsPlaybackState(
    status: status ?? this.status,
    availability: availability ?? this.availability,
    settings: settings ?? this.settings,
    voices: voices ?? this.voices,
    segments: segments ?? this.segments,
    currentIndex: currentIndex ?? this.currentIndex,
    wordStart: clearWordRange ? null : wordStart ?? this.wordStart,
    wordEnd: clearWordRange ? null : wordEnd ?? this.wordEnd,
    error: clearError ? null : error ?? this.error,
  );
}

abstract interface class TtsEngine {
  Future<TtsAvailability> checkAvailability();
  Future<List<TtsVoice>> listVoices();
  Stream<TtsPlaybackEvent> speak(TtsRequest request);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> setRate(double rate);
  Future<void> setVolume(double volume);
}

abstract interface class TtsWakeLock {
  Future<bool> setEnabled(bool enabled);
}

abstract interface class TtsStateStore {
  Future<TtsSettings> loadSettings();
  Future<void> saveSettings(TtsSettings settings);
  Future<TtsCursor?> loadCursor(String bookId);
  Future<void> saveCursor(TtsCursor cursor);
}

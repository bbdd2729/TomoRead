# Android Volume-Key Page Turning Design

## Goal

Allow readers on Android phones to use the hardware volume keys to navigate
backward and forward while reading. The user controls this behavior with a
persisted reading-defaults switch. The setting is not shown on desktop or iOS.

## Scope

- Android only; iOS is explicitly out of scope.
- Both EPUB and plain-text reader workspaces receive volume-key events.
- The feature follows Lumina's approach: Android owns hardware-key
  interception and sends semantic events to Flutter through an event channel.
- The default is disabled. When disabled, volume keys retain their normal
  system behavior.

## Architecture

`ReadingSettings` gains `volumeKeyTurnsPage`, which defaults to `false` and is
included in global reading-default JSON serialization. Existing stored settings
without the field continue to load with the default.

An Android-only native bridge exposes a method channel for enabling and
disabling interception and an event channel for `volume_up` and
`volume_down`. `MainActivity` delegates volume-key down events to the bridge.
The bridge consumes these events only while interception is enabled; otherwise
Android handles them normally.

A Flutter `VolumeControlService` encapsulates the channels and avoids touching
platform channels outside Android. Each active reader subscribes for its
lifetime and updates interception whenever the resolved reader settings
change. Cleanup cancels the subscription and disables interception so leaving
the reader always restores normal volume controls.

## Reader Behavior

- `volume_up` invokes the existing previous-navigation callback.
- `volume_down` invokes the existing next-navigation callback.
- EPUB uses its existing page-or-chapter navigation callbacks, so the behavior
  works in both scrolling and paginated layouts.
- The text reader uses its existing previous/next chapter callbacks.
- Existing callbacks already determine whether navigation is possible; at a
  boundary the event is consumed but does not move the reader.

## Settings UI

The global reading-defaults section adds a `SwitchListTile` labeled
"音量键翻页" with an explanatory subtitle. It is included only when
`defaultTargetPlatform == TargetPlatform.android` and not on the web. Desktop
settings therefore have no new option. Per-book settings remain unchanged;
this is a global default, matching Lumina's reader-wide behavior.

## Error Handling

Method-channel failures are caught and logged without preventing the reader
from opening. A missing or malformed platform event is ignored. Native
interception is disabled during reader disposal regardless of the last setting
value.

## Verification

- Unit tests cover the new settings default, copy behavior, persistence, and
  legacy JSON fallback.
- Widget tests cover Android-only visibility of the toggle and its absence on
  desktop.
- Service tests cover Android channel enable/disable and volume event mapping.
- Reader tests verify the shared handler maps volume-up/down to previous/next
  callbacks.
- Run targeted Flutter tests, formatting, and static analysis. Build or run
  the Android target when the local Android toolchain is available.

# louddd!

`louddd!` is a native, windowless macOS menu bar app for **per-app audio mixing** with a
**native Liquid Glass** UI.

The app is built as a `MenuBarExtra` only:

- no standard app window, no Dock icon (`LSUIElement`)
- compact SwiftUI panel using the macOS 26 **Liquid Glass** APIs (`glassEffect`, `GlassEffectContainer`)
- real per-app volume + live meters via **Core Audio Process Taps**
- output device picker with Bluetooth / transport detection and switching

## Features

- **Per-app volume & mute/solo** — each app producing audio gets an independent slider, mute, and
  solo, with real-time peak/RMS meters.
- **Output device picker** — lists every output device with its transport icon (Bluetooth, AirPods,
  USB, built-in, AirPlay…), best-effort Bluetooth battery, a default checkmark, tap-to-switch, and a
  per-device hardware volume slider.
- **Smart Focus** — duck or prioritize voice apps (e.g. FaceTime) automatically, with manual per-app
  bypass.
- **Persistence** — per-app volumes/mutes (keyed by bundle id) and the last output device are restored
  on relaunch.
- **Live menu-bar meter** — the menu-bar waveform glyph swells with the loudest active app.

## How per-app volume actually works

macOS exposes **no public API to set another app's output volume directly**. `louddd!` implements
real per-app gain with the modern, Apple-sanctioned mechanism (macOS 14.4+), which supersedes shipping
a third-party HAL virtual driver:

1. `AudioProcessTapController` creates a **muted process tap** (`CATapDescription` +
   `AudioHardwareCreateProcessTap`) for each controllable app — routing its audio to our engine.
2. The taps are combined into a **private aggregate device** bound to the chosen output device.
3. An IOProc applies each app's gain, mixes, meters, and renders to the output device.

This requires the **audio-recording permission** (prompted on first use) — see
`NSAudioCaptureUsageDescription` in `Info.plist` and `com.apple.security.device.audio-input` in
`GlassMixer.entitlements`. Output-device switching and per-device volume use fully supported public
APIs and work without that permission.

### Layers

- `SystemAudioProcessBackend` — real backend: process detection + tap engine + device control. Degrades
  to detection-only when audio-recording permission is unavailable.
- `OutputDeviceManager` — output device enumeration, switching, per-device volume/mute, transport/battery.
- `AudioProcessTapController` — the per-app tap + aggregate + render engine.
- `MockAudioBackend` / `VirtualAudioDriverBackend` — simulation + forwarding boundary for UI work.

## Custom icons

Icons live in `GlassMixer/Assets.xcassets`. Open it in Xcode and drag images into the wells (the sets
are pre-created and wired up — until you add images, the app falls back to SF Symbols, so nothing is
blank):

- **App icon** → `AppIcon` set. Drop a 1024×1024 PNG (use the inspector's *Single Size* option, or fill
  the 16–512 @1x/@2x wells). Already set as the target's app icon.
- **Menu-bar icon** → `MenuBarIcon` set. Add a small monochrome image (~18pt, PDF or @1x/@2x/@3x PNG);
  it's marked as a *template* so macOS tints it for light/dark menu bars automatically.
- **Per-app fallback icon** → `AppPlaceholder` set. Shown for apps whose real icon can't be resolved
  (real app icons otherwise come from the system automatically).
- **Panel logo** → `PanelLogo` set. The badge at the top-left of the panel (clipped to a 38pt circle);
  falls back to the gradient waveform badge until you add an image.

## Requirements

- **macOS 26 (Tahoe)** and **Xcode 26** — required for the native Liquid Glass APIs.

## Run

```zsh
zsh script/build_and_run.sh
```

The built app is:

```text
work/DerivedData/Build/Products/Debug/louddd!.app
```

> To exercise real per-app volume the app must be **signed with the entitlement** (set a
> `DEVELOPMENT_TEAM`, or sign ad-hoc). Grant the audio-recording permission on first launch. For
> UI-only work without permission, launch with `--demo-audio` to drive the mock backend.

## Xcode

Open `louddd!.xcodeproj`. The project, target, and scheme are all named `louddd!`. The source folder
is `GlassMixer/` for internal path stability.

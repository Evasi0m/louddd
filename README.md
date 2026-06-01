# louddd!

`louddd!` is a native, windowless macOS menu bar app prototype for per-app audio mixing.

The app is intentionally built as a `MenuBarExtra` only:

- no standard app window
- no Dock icon via `LSUIElement`
- compact SwiftUI liquid glass panel
- CoreAudio process detection for apps currently running output audio
- virtual-driver backend boundary for real per-app gain control

## Current State

macOS does not allow a normal app to directly change arbitrary per-app output volume through public CoreAudio APIs. `louddd!` therefore separates the app into two layers:

- `SystemAudioProcessBackend`: detects apps that are currently producing output audio, such as Safari playing YouTube.
- `VirtualAudioDriverBackend`: placeholder boundary for the real virtual audio device / mixer / XPC agent path required for actual per-app gain control.

Detected apps can appear before the virtual driver exists, but real per-app volume control requires routing audio through the virtual mixer backend.

## Run

```zsh
zsh script/build_and_run.sh
```

The built app is:

```text
work/DerivedData/Build/Products/Debug/louddd!.app
```

## Xcode

Open:

```text
GlassMixer.xcodeproj
```

The internal project/target name is still `GlassMixer` for Xcode project stability, but the product name, bundle display, and app UI are `louddd!`.

## Menu Bar Only

`GlassMixer/Info.plist` contains:

```xml
<key>LSUIElement</key>
<true/>
```

That keeps the app out of the Dock and makes it run as a status bar utility.


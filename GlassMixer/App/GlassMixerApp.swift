import AppKit
import SwiftUI

@main
struct GlassMixerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = MixerStore(
        service: AudioControlService(
            backend: AudioBackendFactory.makeDefaultBackend()
        )
    )

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(store: store)
                .frame(width: 390)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Live menu-bar icon: the waveform glyph swells with the loudest active app via SF Symbols'
/// variable-value rendering, so the meter is visible without opening the panel.
private struct MenuBarLabel: View {
    var store: MixerStore

    var body: some View {
        let peak = store.apps.map(\.peakLevel).max() ?? 0
        Image(systemName: "waveform", variableValue: max(0.12, min(peak, 1)))
    }
}

enum AudioBackendFactory {
    static func makeDefaultBackend() -> AudioBackend {
        if ProcessInfo.processInfo.arguments.contains("--demo-audio") {
            return VirtualAudioDriverBackend(fallback: MockAudioBackend())
        }

        if ProcessInfo.processInfo.arguments.contains("--virtual-driver") {
            return VirtualAudioDriverBackend()
        }

        return SystemAudioProcessBackend()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

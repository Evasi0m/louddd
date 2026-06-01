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
            Image(systemName: "waveform.circle.fill")
        }
        .menuBarExtraStyle(.window)
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

import Foundation
import Observation

@MainActor
@Observable
final class MixerStore {
    let service: AudioControlService

    var focusProfile = FocusProfile() {
        didSet {
            service.applyFocusProfile(focusProfile)
        }
    }

    init(service: AudioControlService) {
        self.service = service
    }

    var apps: [AudioApp] {
        service.apps
    }

    var outputDeviceName: String {
        service.currentOutputDevice?.name ?? "Output Device"
    }

    var lastError: String? {
        service.lastError
    }

    func start() {
        service.start()
    }

    func setVolume(_ volume: Double, for app: AudioApp) {
        service.setVolume(volume, for: app)
    }

    func toggleFocus() {
        focusProfile.isEnabled.toggle()
    }

    func toggleManualBypass(for app: AudioApp) {
        if focusProfile.manuallyBypassedAppIDs.contains(app.id) {
            focusProfile.manuallyBypassedAppIDs.remove(app.id)
        } else {
            focusProfile.manuallyBypassedAppIDs.insert(app.id)
        }
    }
}

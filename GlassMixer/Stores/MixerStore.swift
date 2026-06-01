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

    init(service: AudioControlService, preferences: PreferencesStore = PreferencesStore()) {
        self.service = service
        self.focusProfile.isEnabled = preferences.focusEnabled
    }

    // MARK: - Apps

    var apps: [AudioApp] {
        service.apps
    }

    var soloedAppID: AudioApp.ID? {
        service.soloedAppID
    }

    // MARK: - Devices

    var availableDevices: [AudioDevice] {
        service.availableDevices
    }

    var currentOutputDevice: AudioDevice? {
        service.currentOutputDevice
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

    // MARK: - Per-app actions

    func setVolume(_ volume: Double, for app: AudioApp) {
        service.setVolume(volume, for: app)
    }

    func toggleMute(for app: AudioApp) {
        service.setMute(!app.isMuted, for: app)
    }

    func toggleSolo(for app: AudioApp) {
        service.toggleSolo(for: app)
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

    // MARK: - Device actions

    func selectDevice(_ device: AudioDevice) {
        service.selectDevice(device)
    }

    func setDeviceVolume(_ volume: Double, for device: AudioDevice) {
        service.setDeviceVolume(volume, for: device)
    }

    func setDeviceMute(_ muted: Bool, for device: AudioDevice) {
        service.setDeviceMute(muted, for: device)
    }
}

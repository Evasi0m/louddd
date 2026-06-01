import Foundation
import Observation

@MainActor
@Observable
final class AudioControlService {
    private let backend: AudioBackend
    private let preferences: PreferencesStore
    private var startTask: Task<Void, Never>?
    private var appUpdatesTask: Task<Void, Never>?
    private var deviceUpdatesTask: Task<Void, Never>?
    private var deviceListTask: Task<Void, Never>?

    /// Bundle ids whose saved volume/mute we've already restored this session.
    private var restoredBundleIDs: Set<String> = []
    /// App id currently soloed (others muted), nil when no solo is active.
    private(set) var soloedAppID: AudioApp.ID?

    var apps: [AudioApp] = []
    var availableDevices: [AudioDevice] = []
    var currentOutputDevice: AudioDevice?
    var isRunning = false
    var lastError: String?

    init(backend: AudioBackend, preferences: PreferencesStore = PreferencesStore()) {
        self.backend = backend
        self.preferences = preferences
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil

        appUpdatesTask = Task { [weak self] in
            guard let self else { return }
            for await updatedApps in backend.appUpdates {
                self.ingest(updatedApps)
            }
        }

        deviceUpdatesTask = Task { [weak self] in
            guard let self else { return }
            for await device in backend.deviceUpdates {
                self.currentOutputDevice = device
            }
        }

        deviceListTask = Task { [weak self] in
            guard let self else { return }
            for await devices in backend.deviceListUpdates {
                self.availableDevices = devices
                if let current = devices.first(where: { $0.isDefaultOutput }) {
                    self.currentOutputDevice = current
                }
            }
        }

        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await backend.start()
            } catch {
                if let backendError = error as? AudioBackendError,
                   case .driverUnavailable = backendError {
                    self.lastError = nil
                } else {
                    self.lastError = error.localizedDescription
                }
                self.isRunning = false
            }
        }
    }

    func stop() {
        [startTask, appUpdatesTask, deviceUpdatesTask, deviceListTask].forEach { $0?.cancel() }
        startTask = nil
        appUpdatesTask = nil
        deviceUpdatesTask = nil
        deviceListTask = nil
        isRunning = false
        Task { await backend.stop() }
    }

    // MARK: - App list ingestion + persistence restore

    private func ingest(_ updatedApps: [AudioApp]) {
        var visibleApps = updatedApps
            .filter { $0.isMixable && ($0.isAudible || $0.isMuted) && ($0.peakLevel > 0.035 || $0.isMuted) }
            .sorted { lhs, rhs in
                if lhs.isFaceTimeCandidate != rhs.isFaceTimeCandidate {
                    return lhs.isFaceTimeCandidate
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

        // Restore persisted per-app volume/mute the first time we see each bundle this session.
        for index in visibleApps.indices {
            let app = visibleApps[index]
            guard let bundleID = app.bundleIdentifier, !restoredBundleIDs.contains(bundleID) else { continue }
            restoredBundleIDs.insert(bundleID)

            if let savedVolume = preferences.volume(forBundleID: bundleID), app.canControlVolume {
                visibleApps[index].volume = savedVolume
                applyVolume(savedVolume, forAppID: app.id)
            }
            if preferences.isMuted(forBundleID: bundleID), app.canControlVolume {
                visibleApps[index].isMuted = true
                applyMute(true, forAppID: app.id)
            }
        }

        apps = visibleApps
    }

    // MARK: - Per-app controls

    func setVolume(_ volume: Double, for app: AudioApp) {
        let sanitized = min(max(volume, 0), 1.5)
        if let index = apps.firstIndex(where: { $0.id == app.id }) {
            apps[index].volume = sanitized
        }
        if let bundleID = app.bundleIdentifier {
            preferences.setVolume(sanitized, forBundleID: bundleID)
        }
        applyVolume(sanitized, forAppID: app.id)
    }

    func setMute(_ muted: Bool, for app: AudioApp) {
        if let index = apps.firstIndex(where: { $0.id == app.id }) {
            apps[index].isMuted = muted
        }
        if let bundleID = app.bundleIdentifier {
            preferences.setMuted(muted, forBundleID: bundleID)
        }
        applyMute(muted, forAppID: app.id)
    }

    /// Solo: mute every other controllable app. Tapping the soloed app again clears solo.
    func toggleSolo(for app: AudioApp) {
        if soloedAppID == app.id {
            soloedAppID = nil
            for other in apps { setMute(false, for: other) }
            return
        }
        soloedAppID = app.id
        for other in apps {
            setMute(other.id != app.id, for: other)
        }
    }

    private func applyVolume(_ volume: Double, forAppID id: AudioApp.ID) {
        Task {
            do {
                try await backend.setVolume(volume, for: id)
            } catch {
                self.surface(error)
            }
        }
    }

    private func applyMute(_ muted: Bool, forAppID id: AudioApp.ID) {
        Task {
            do {
                try await backend.setMute(muted, for: id)
            } catch {
                self.surface(error)
            }
        }
    }

    func applyFocusProfile(_ profile: FocusProfile) {
        preferences.focusEnabled = profile.isEnabled
        Task {
            do {
                try await backend.setFocusProfile(profile)
            } catch {
                self.surface(error)
            }
        }
    }

    // MARK: - Output device controls

    func selectDevice(_ device: AudioDevice) {
        preferences.lastOutputDeviceUID = device.uid
        Task {
            do {
                try await backend.setDefaultOutputDevice(device.id)
            } catch {
                self.surface(error)
            }
        }
    }

    func setDeviceVolume(_ volume: Double, for device: AudioDevice) {
        if let index = availableDevices.firstIndex(where: { $0.id == device.id }) {
            availableDevices[index].volume = volume
        }
        Task {
            do {
                try await backend.setDeviceVolume(volume, for: device.id)
            } catch {
                self.surface(error)
            }
        }
    }

    func setDeviceMute(_ muted: Bool, for device: AudioDevice) {
        Task {
            do {
                try await backend.setDeviceMute(muted, for: device.id)
            } catch {
                self.surface(error)
            }
        }
    }

    private func surface(_ error: Error) {
        if let backendError = error as? AudioBackendError, case .driverUnavailable = backendError {
            return
        }
        lastError = error.localizedDescription
    }
}

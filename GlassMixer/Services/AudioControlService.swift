import Foundation
import Observation

@MainActor
@Observable
final class AudioControlService {
    private let backend: AudioBackend
    private var startTask: Task<Void, Never>?
    private var appUpdatesTask: Task<Void, Never>?
    private var deviceUpdatesTask: Task<Void, Never>?

    var apps: [AudioApp] = []
    var currentOutputDevice: AudioDevice?
    var isRunning = false
    var lastError: String?

    init(backend: AudioBackend) {
        self.backend = backend
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil

        appUpdatesTask = Task { [weak self] in
            guard let self else { return }
            for await updatedApps in backend.appUpdates {
                let visibleApps = updatedApps
                    .filter { $0.isMixable && $0.isAudible && $0.peakLevel > 0.035 }
                    .sorted { lhs, rhs in
                        if lhs.isFaceTimeCandidate != rhs.isFaceTimeCandidate {
                            return lhs.isFaceTimeCandidate
                        }
                        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                    }
                self.apps = visibleApps
            }
        }

        deviceUpdatesTask = Task { [weak self] in
            guard let self else { return }
            for await device in backend.deviceUpdates {
                self.currentOutputDevice = device
            }
        }

        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await backend.start()
            } catch {
                await MainActor.run {
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
    }

    func stop() {
        startTask?.cancel()
        appUpdatesTask?.cancel()
        deviceUpdatesTask?.cancel()
        startTask = nil
        appUpdatesTask = nil
        deviceUpdatesTask = nil
        isRunning = false

        Task {
            await backend.stop()
        }
    }

    func setVolume(_ volume: Double, for app: AudioApp) {
        let sanitizedVolume = min(max(volume, 0), 1.5)

        if let index = apps.firstIndex(where: { $0.id == app.id }) {
            apps[index].volume = sanitizedVolume
        }

        Task {
            do {
                try await backend.setVolume(sanitizedVolume, for: app.id)
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    func applyFocusProfile(_ profile: FocusProfile) {
        Task {
            do {
                try await backend.setFocusProfile(profile)
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                }
            }
        }
    }
}

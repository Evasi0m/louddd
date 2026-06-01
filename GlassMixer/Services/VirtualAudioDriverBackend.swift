import Foundation

actor VirtualAudioDriverBackend: AudioBackend {
    private let fallback: AudioBackend?
    private var appContinuation: AsyncStream<[AudioApp]>.Continuation?
    private var deviceContinuation: AsyncStream<AudioDevice?>.Continuation?
    private var forwardingTasks: [Task<Void, Never>] = []

    init(fallback: AudioBackend? = nil) {
        self.fallback = fallback
    }

    static func fallbackToMockWhenUnavailable() -> AudioBackend {
        VirtualAudioDriverBackend(fallback: MockAudioBackend())
    }

    nonisolated var appUpdates: AsyncStream<[AudioApp]> {
        AsyncStream { continuation in
            Task { await self.setAppContinuation(continuation) }
        }
    }

    nonisolated var deviceUpdates: AsyncStream<AudioDevice?> {
        AsyncStream { continuation in
            Task { await self.setDeviceContinuation(continuation) }
        }
    }

    func start() async throws {
        if let fallback {
            try await fallback.start()
            forwardingTasks.append(Task {
                for await apps in fallback.appUpdates {
                    self.yieldApps(apps)
                }
            })
            forwardingTasks.append(Task {
                for await device in fallback.deviceUpdates {
                    self.yieldDevice(device)
                }
            })
            return
        }

        throw AudioBackendError.driverUnavailable
    }

    func stop() async {
        forwardingTasks.forEach { $0.cancel() }
        forwardingTasks.removeAll()
        await fallback?.stop()
    }

    func setVolume(_ volume: Double, for appID: AudioApp.ID) async throws {
        guard (0...1.5).contains(volume) else { throw AudioBackendError.invalidVolume }

        if let fallback {
            try await fallback.setVolume(volume, for: appID)
            return
        }

        // Production hook: send `setGain(volume, forSession: appID)` to the audio agent over XPC.
        throw AudioBackendError.driverUnavailable
    }

    func setFocusProfile(_ profile: FocusProfile) async throws {
        if let fallback {
            try await fallback.setFocusProfile(profile)
            return
        }

        // Production hook: send the focus policy to the mixer engine inside the audio agent.
        throw AudioBackendError.driverUnavailable
    }

    private func setAppContinuation(_ continuation: AsyncStream<[AudioApp]>.Continuation) {
        appContinuation = continuation
    }

    private func setDeviceContinuation(_ continuation: AsyncStream<AudioDevice?>.Continuation) {
        deviceContinuation = continuation
    }

    private func yieldApps(_ apps: [AudioApp]) {
        appContinuation?.yield(apps)
    }

    private func yieldDevice(_ device: AudioDevice?) {
        deviceContinuation?.yield(device)
    }
}

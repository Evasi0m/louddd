import Foundation

/// Optional boundary that forwards to a fallback backend (e.g. the mock) when present, and otherwise
/// reports unavailable. Retained as a documented alternative path; the primary real implementation is
/// `SystemAudioProcessBackend` + `AudioProcessTapController`.
actor VirtualAudioDriverBackend: AudioBackend {
    private let fallback: AudioBackend?
    private var appContinuation: AsyncStream<[AudioApp]>.Continuation?
    private var deviceContinuation: AsyncStream<AudioDevice?>.Continuation?
    private var deviceListContinuation: AsyncStream<[AudioDevice]>.Continuation?
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

    nonisolated var deviceListUpdates: AsyncStream<[AudioDevice]> {
        AsyncStream { continuation in
            Task { await self.setDeviceListContinuation(continuation) }
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
            forwardingTasks.append(Task {
                for await devices in fallback.deviceListUpdates {
                    self.yieldDeviceList(devices)
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
        guard let fallback else { throw AudioBackendError.driverUnavailable }
        try await fallback.setVolume(volume, for: appID)
    }

    func setMute(_ muted: Bool, for appID: AudioApp.ID) async throws {
        guard let fallback else { throw AudioBackendError.driverUnavailable }
        try await fallback.setMute(muted, for: appID)
    }

    func setFocusProfile(_ profile: FocusProfile) async throws {
        guard let fallback else { throw AudioBackendError.driverUnavailable }
        try await fallback.setFocusProfile(profile)
    }

    func setDefaultOutputDevice(_ deviceID: AudioDevice.ID) async throws {
        guard let fallback else { throw AudioBackendError.driverUnavailable }
        try await fallback.setDefaultOutputDevice(deviceID)
    }

    func setDeviceVolume(_ volume: Double, for deviceID: AudioDevice.ID) async throws {
        guard let fallback else { throw AudioBackendError.driverUnavailable }
        try await fallback.setDeviceVolume(volume, for: deviceID)
    }

    func setDeviceMute(_ muted: Bool, for deviceID: AudioDevice.ID) async throws {
        guard let fallback else { throw AudioBackendError.driverUnavailable }
        try await fallback.setDeviceMute(muted, for: deviceID)
    }

    private func setAppContinuation(_ continuation: AsyncStream<[AudioApp]>.Continuation) {
        appContinuation = continuation
    }

    private func setDeviceContinuation(_ continuation: AsyncStream<AudioDevice?>.Continuation) {
        deviceContinuation = continuation
    }

    private func setDeviceListContinuation(_ continuation: AsyncStream<[AudioDevice]>.Continuation) {
        deviceListContinuation = continuation
    }

    private func yieldApps(_ apps: [AudioApp]) {
        appContinuation?.yield(apps)
    }

    private func yieldDevice(_ device: AudioDevice?) {
        deviceContinuation?.yield(device)
    }

    private func yieldDeviceList(_ devices: [AudioDevice]) {
        deviceListContinuation?.yield(devices)
    }
}

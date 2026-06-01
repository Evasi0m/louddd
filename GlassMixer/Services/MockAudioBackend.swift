import Foundation

actor MockAudioBackend: AudioBackend {
    private var appContinuation: AsyncStream<[AudioApp]>.Continuation?
    private var deviceContinuation: AsyncStream<AudioDevice?>.Continuation?
    private var deviceListContinuation: AsyncStream<[AudioDevice]>.Continuation?
    private var simulationTask: Task<Void, Never>?
    private var volumes: [AudioApp.ID: Double] = [:]
    private var mutes: Set<AudioApp.ID> = []
    private var focusProfile = FocusProfile()
    private var selectedDeviceID: AudioObjectID = 1

    private let devices: [AudioDevice] = [
        AudioDevice(id: 1, uid: "BuiltInSpeaker", name: "MacBook Pro Speakers", isDefaultOutput: true, transport: .builtIn, volume: 0.7),
        AudioDevice(id: 2, uid: "AirPodsPro", name: "AirPods Pro", isDefaultOutput: false, transport: .bluetooth, volume: 0.55, batteryPercent: 82),
        AudioDevice(id: 3, uid: "StudioDisplay", name: "Studio Display Speakers", isDefaultOutput: false, transport: .displayPort, volume: 0.5),
        AudioDevice(id: 4, uid: "USBInterface", name: "Scarlett 2i2 USB", isDefaultOutput: false, transport: .usb, volume: 0.8)
    ]

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
        guard simulationTask == nil else { return }

        publishDevices()

        simulationTask = Task {
            var tick = 0.0
            while !Task.isCancelled {
                tick += 0.18

                let apps = [
                    makeApp(pid: 100, bundleID: "com.apple.FaceTime", name: "FaceTime", tick: tick, basePeak: 0.72, isFaceTime: true, isMixable: true, audibleWindow: 0.92),
                    makeApp(pid: 200, bundleID: "com.apple.Safari", name: "Safari", tick: tick + 1.8, basePeak: 0.54, isFaceTime: false, isMixable: true, audibleWindow: 0.68),
                    makeApp(pid: 300, bundleID: "com.apple.TV", name: "TV", tick: tick + 3.4, basePeak: 0.62, isFaceTime: false, isMixable: true, audibleWindow: 0.48),
                    makeApp(pid: 400, bundleID: "com.apple.Notes", name: "Notes", tick: tick + 0.4, basePeak: 0.20, isFaceTime: false, isMixable: false, audibleWindow: 0.85)
                ]

                appContinuation?.yield(apps)

                try? await Task.sleep(for: .milliseconds(140))
            }
        }
    }

    func stop() async {
        simulationTask?.cancel()
        simulationTask = nil
    }

    func setVolume(_ volume: Double, for appID: AudioApp.ID) async throws {
        guard (0...1.5).contains(volume) else { throw AudioBackendError.invalidVolume }
        volumes[appID] = volume
    }

    func setMute(_ muted: Bool, for appID: AudioApp.ID) async throws {
        if muted { mutes.insert(appID) } else { mutes.remove(appID) }
    }

    func setFocusProfile(_ profile: FocusProfile) async throws {
        focusProfile = profile
        guard profile.isEnabled else { return }

        for id in volumes.keys where !profile.shouldBypass(appID: id) {
            if id.contains("FaceTime") {
                volumes[id] = profile.faceTimeVolume
            }
        }
    }

    func setDefaultOutputDevice(_ deviceID: AudioDevice.ID) async throws {
        guard devices.contains(where: { $0.id == deviceID }) else {
            throw AudioBackendError.deviceUnavailable
        }
        selectedDeviceID = deviceID
        publishDevices()
    }

    func setDeviceVolume(_ volume: Double, for deviceID: AudioDevice.ID) async throws {
        guard devices.contains(where: { $0.id == deviceID }) else {
            throw AudioBackendError.deviceUnavailable
        }
    }

    func setDeviceMute(_ muted: Bool, for deviceID: AudioDevice.ID) async throws {}

    private func publishDevices() {
        let list = devices.map { device -> AudioDevice in
            var copy = device
            copy.isDefaultOutput = device.id == selectedDeviceID
            return copy
        }
        deviceListContinuation?.yield(list)
        deviceContinuation?.yield(list.first { $0.isDefaultOutput })
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

    private func makeApp(
        pid: pid_t,
        bundleID: String,
        name: String,
        tick: Double,
        basePeak: Double,
        isFaceTime: Bool,
        isMixable: Bool,
        audibleWindow: Double
    ) -> AudioApp {
        let id = AudioApp.identity(processID: pid, bundleIdentifier: bundleID)
        let pulse = (sin(tick) + 1) / 2
        let phraseGate = ((sin(tick * 0.31) + 1) / 2) < audibleWindow
        let isMuted = mutes.contains(id)
        let focusVolume = isFaceTime && focusProfile.isEnabled && !focusProfile.shouldBypass(appID: id)
            ? focusProfile.faceTimeVolume
            : (volumes[id] ?? (isFaceTime ? 1.0 : 0.65))
        let rawPeak = phraseGate ? max(0.04, min(1.0, basePeak * (0.58 + pulse * 0.52))) : 0
        let animatedPeak = isMuted ? 0 : rawPeak

        return AudioApp(
            id: id,
            processID: pid,
            bundleIdentifier: bundleID,
            displayName: name,
            iconPathHint: nil,
            volume: focusVolume,
            isMuted: isMuted,
            isMixable: isMixable,
            canControlVolume: true,
            isAudible: rawPeak > 0.035,
            peakLevel: animatedPeak,
            rmsLevel: animatedPeak * 0.72,
            isFaceTimeCandidate: isFaceTime
        )
    }
}

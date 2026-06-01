import AppKit
import CoreAudio
import Foundation

actor SystemAudioProcessBackend: AudioBackend {
    private var appContinuation: AsyncStream<[AudioApp]>.Continuation?
    private var deviceContinuation: AsyncStream<AudioDevice?>.Continuation?
    private var pollingTask: Task<Void, Never>?
    private let deviceObserver = AudioDeviceObserver()

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
        guard pollingTask == nil else { return }

        deviceContinuation?.yield(deviceObserver.currentDefaultOutputDevice())
        deviceObserver.start { [weak self] in
            Task {
                guard let self else { return }
                await self.yieldCurrentDevice()
            }
        }

        pollingTask = Task {
            while !Task.isCancelled {
                let apps = Self.scanRunningOutputProcesses()
                self.yieldApps(apps)
                try? await Task.sleep(for: .milliseconds(650))
            }
        }
    }

    func stop() async {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func setVolume(_ volume: Double, for appID: AudioApp.ID) async throws {
        throw AudioBackendError.driverUnavailable
    }

    func setFocusProfile(_ profile: FocusProfile) async throws {
        // Focus policy requires the virtual mixer path. Detection-only mode observes streams.
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

    private func yieldCurrentDevice() {
        deviceContinuation?.yield(deviceObserver.currentDefaultOutputDevice())
    }

    private static func scanRunningOutputProcesses() -> [AudioApp] {
        processObjectIDs().compactMap { processObjectID in
            guard
                let pid = pid(for: processObjectID),
                isRunningOutput(processObjectID)
            else {
                return nil
            }

            let bundleID = bundleIdentifier(for: processObjectID)
            let runningApp = NSRunningApplication(processIdentifier: pid)
            let displayName = runningApp?.localizedName
                ?? bundleID?.components(separatedBy: ".").last
                ?? "Process \(pid)"
            let id = AudioApp.identity(processID: pid, bundleIdentifier: bundleID)
            let isFaceTime = bundleID == "com.apple.FaceTime" || displayName.localizedCaseInsensitiveContains("FaceTime")

            return AudioApp(
                id: id,
                processID: pid,
                bundleIdentifier: bundleID,
                displayName: displayName,
                iconPathHint: runningApp?.bundleURL?.path,
                volume: 1,
                isMixable: true,
                canControlVolume: false,
                isAudible: true,
                peakLevel: 0.72,
                rmsLevel: 0.5,
                isFaceTimeCandidate: isFaceTime
            )
        }
    }

    private static func processObjectIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard sizeStatus == noErr, dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var processIDs = Array(repeating: AudioObjectID(), count: count)
        let dataStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &processIDs
        )

        guard dataStatus == noErr else { return [] }
        return processIDs.filter { $0 != kAudioObjectUnknown }
    }

    private static func pid(for processObjectID: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var value = pid_t()
        var dataSize = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectGetPropertyData(processObjectID, &address, 0, nil, &dataSize, &value)
        guard status == noErr else { return nil }
        return value
    }

    private static func bundleIdentifier(for processObjectID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var unmanagedValue: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(processObjectID, &address, 0, nil, &dataSize, &unmanagedValue)
        guard status == noErr, let unmanagedValue else { return nil }
        let bundleID = unmanagedValue.takeRetainedValue() as String
        return bundleID.isEmpty ? nil : bundleID
    }

    private static func isRunningOutput(_ processObjectID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var value = UInt32()
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(processObjectID, &address, 0, nil, &dataSize, &value)
        guard status == noErr else { return false }
        return value != 0
    }
}

import AppKit
import CoreAudio
import Foundation

/// Real backend: enumerates apps producing output audio (CoreAudio process objects), drives the
/// `AudioProcessTapController` for genuine per-app gain + live metering, and uses `OutputDeviceManager`
/// for the fully supported device controls (switch default output, per-device volume/mute, Bluetooth
/// transport + battery).
///
/// When audio-recording permission is unavailable the backend degrades gracefully to detection-only:
/// apps are still listed, but `canControlVolume` is false until permission is granted.
actor SystemAudioProcessBackend: AudioBackend {
    private var appContinuation: AsyncStream<[AudioApp]>.Continuation?
    private var deviceContinuation: AsyncStream<AudioDevice?>.Continuation?
    private var deviceListContinuation: AsyncStream<[AudioDevice]>.Continuation?
    private var pollingTask: Task<Void, Never>?

    private let deviceManager = OutputDeviceManager()
    private let tapController = AudioProcessTapController()

    private var gains: [AudioApp.ID: Double] = [:]
    private var mutes: Set<AudioApp.ID> = []
    private var focusProfile = FocusProfile()
    private var controlledIDs: Set<AudioApp.ID> = []
    private var engineActive = false
    private var ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)

    /// Latest metadata + last-audible timestamp per app, used to keep the visible list stable.
    /// Tapping an app mutes its normal output (so `isRunningOutput`/peak briefly read zero); without
    /// hysteresis that caused the row to flicker in and out. We keep an app for a short grace window
    /// after it last showed output *or* real metered activity.
    private var knownApps: [AudioApp.ID: AudioApp] = [:]
    private var lastAudibleAt: [AudioApp.ID: Date] = [:]
    private let visibilityGrace: TimeInterval = 2.5
    private let meterActivityThreshold: Double = 0.02

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

    // MARK: - Lifecycle

    func start() async throws {
        guard pollingTask == nil else { return }

        publishDevices()
        deviceManager.start { [weak self] in
            Task { await self?.publishDevices() }
        }

        // Start the per-app engine if the user has granted audio-recording permission.
        if AudioProcessTapController.hasPermission() {
            engineActive = true
            await tapController.start(outputDeviceUID: deviceManager.currentDefaultOutputDevice()?.uid)
        }

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    func stop() async {
        pollingTask?.cancel()
        pollingTask = nil
        await tapController.stop()
        engineActive = false
    }

    // MARK: - Per-app mixing

    func setVolume(_ volume: Double, for appID: AudioApp.ID) async throws {
        guard (0...1.5).contains(volume) else { throw AudioBackendError.invalidVolume }
        gains[appID] = volume
        guard engineActive else { throw AudioBackendError.permissionDenied }
        await tapController.setGain(volume, for: appID)
    }

    func setMute(_ muted: Bool, for appID: AudioApp.ID) async throws {
        if muted { mutes.insert(appID) } else { mutes.remove(appID) }
        guard engineActive else { throw AudioBackendError.permissionDenied }
        await tapController.setMuted(muted, for: appID)
    }

    func setFocusProfile(_ profile: FocusProfile) async throws {
        focusProfile = profile
        guard engineActive else { return }
        await applyFocusGains()
    }

    // MARK: - Output device control

    func setDefaultOutputDevice(_ deviceID: AudioDevice.ID) async throws {
        do {
            try deviceManager.setDefaultOutputDevice(deviceID)
        } catch {
            throw AudioBackendError.deviceUnavailable
        }
        let uid = deviceManager.currentDefaultOutputDevice()?.uid
        await tapController.updateOutputDevice(uid: uid)
        publishDevices()
    }

    func setDeviceVolume(_ volume: Double, for deviceID: AudioDevice.ID) async throws {
        do {
            try deviceManager.setVolume(volume, for: deviceID)
        } catch {
            throw AudioBackendError.commandRejected("This device has no adjustable hardware volume.")
        }
        publishDevices()
    }

    func setDeviceMute(_ muted: Bool, for deviceID: AudioDevice.ID) async throws {
        do {
            try deviceManager.setMute(muted, for: deviceID)
        } catch {
            throw AudioBackendError.commandRejected("This device cannot be muted in hardware.")
        }
        publishDevices()
    }

    // MARK: - Polling

    private func tick() async {
        let now = Date()
        let meters = engineActive ? await tapController.meters() : [:]

        // Apps the system reports as actively running output right now.
        for app in Self.scanRunningOutputProcesses(excludingPID: ownPID) {
            knownApps[app.id] = app
            lastAudibleAt[app.id] = now
        }

        // Apps we're tapping count as audible while their metered level is non-trivial, even though
        // their normal output is muted (which is why we can't rely on isRunningOutput for them).
        for (id, meter) in meters where max(meter.peak, meter.rms) > meterActivityThreshold {
            if knownApps[id] != nil {
                lastAudibleAt[id] = now
            }
        }

        // Expire anything past the grace window; keep the rest as the visible candidate set.
        var expired: [AudioApp.ID] = []
        var candidates: [AudioApp] = []
        for (id, lastSeen) in lastAudibleAt {
            if now.timeIntervalSince(lastSeen) > visibilityGrace {
                expired.append(id)
            } else if let base = knownApps[id] {
                candidates.append(base)
            }
        }
        for id in expired {
            lastAudibleAt[id] = nil
            knownApps[id] = nil
        }

        if engineActive {
            controlledIDs = await tapController.reconcile(controllableApps: candidates)
        }

        let apps = candidates.map { base -> AudioApp in
            var app = base
            let meter = meters[app.id]
            app.volume = gains[app.id] ?? 1
            app.isMuted = mutes.contains(app.id)
            app.canControlVolume = engineActive && controlledIDs.contains(app.id)
            app.isAudible = true
            if app.isMuted {
                app.peakLevel = 0
                app.rmsLevel = 0
            } else if engineActive {
                app.peakLevel = meter?.peak ?? 0
                app.rmsLevel = meter?.rms ?? 0
            } else {
                // Detection-only (no audio-recording permission): no real meters available.
                app.peakLevel = 0.5
                app.rmsLevel = 0.32
            }
            return app
        }

        appContinuation?.yield(apps)
    }

    private func applyFocusGains() async {
        guard focusProfile.isEnabled else { return }
        for id in controlledIDs where !focusProfile.shouldBypass(appID: id) {
            if id.localizedCaseInsensitiveContains("FaceTime") {
                gains[id] = focusProfile.faceTimeVolume
                await tapController.setGain(focusProfile.faceTimeVolume, for: id)
            }
        }
    }

    private func publishDevices() {
        let devices = deviceManager.outputDevices()
        deviceListContinuation?.yield(devices)
        deviceContinuation?.yield(devices.first { $0.isDefaultOutput } ?? deviceManager.currentDefaultOutputDevice())
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

    // MARK: - Process enumeration (CoreAudio)

    private static func scanRunningOutputProcesses(excludingPID excluded: pid_t) -> [AudioApp] {
        processObjectIDs().compactMap { processObjectID in
            guard
                let pid = pid(for: processObjectID),
                pid != excluded,
                isRunningOutput(processObjectID)
            else {
                return nil
            }

            let owner = resolveOwner(pid: pid, audioBundleID: bundleIdentifier(for: processObjectID))
            let id = AudioApp.identity(processID: pid, bundleIdentifier: owner.bundleID)
            let isFaceTime = owner.bundleID == "com.apple.FaceTime"
                || owner.name.localizedCaseInsensitiveContains("FaceTime")

            return AudioApp(
                id: id,
                processID: pid,
                bundleIdentifier: owner.bundleID,
                displayName: owner.name,
                iconPathHint: owner.iconPath,
                volume: 1,
                isMuted: false,
                isMixable: true,
                canControlVolume: false,
                isAudible: true,
                peakLevel: 0,
                rmsLevel: 0,
                isFaceTimeCandidate: isFaceTime
            )
        }
    }

    private struct ResolvedOwner {
        let bundleID: String?
        let name: String
        let iconPath: String?
    }

    /// Resolve (and cache) the owning app for an audio pid. Caching keeps a process's identity stable
    /// across polls — re-resolving every tick occasionally returned the helper instead of the parent
    /// app, which flipped the app id and made the row jump/jitter.
    private static var ownerCache: [pid_t: ResolvedOwner] = [:]

    private static func resolveOwner(pid: pid_t, audioBundleID: String?) -> ResolvedOwner {
        if let cached = ownerCache[pid] {
            return cached
        }
        let owner = ProcessAppResolver.owningApplication(pid: pid)
        let resolved = ResolvedOwner(
            bundleID: owner?.bundleIdentifier ?? audioBundleID,
            name: owner?.localizedName
                ?? audioBundleID?.components(separatedBy: ".").last
                ?? "Process \(pid)",
            iconPath: owner?.bundleURL?.path
        )
        ownerCache[pid] = resolved
        if ownerCache.count > 128 {
            ownerCache.removeAll(keepingCapacity: true)
        }
        return resolved
    }

    private static func processObjectIDs() -> [AudioObjectID] {
        (try? CoreAudioProperty.array(
            CoreAudioProperty.systemObject,
            CoreAudioProperty.address(kAudioHardwarePropertyProcessObjectList),
            of: AudioObjectID.self
        ))?.filter { $0 != kAudioObjectUnknown } ?? []
    }

    private static func pid(for processObjectID: AudioObjectID) -> pid_t? {
        try? CoreAudioProperty.value(
            processObjectID,
            CoreAudioProperty.address(kAudioProcessPropertyPID),
            default: pid_t()
        )
    }

    private static func bundleIdentifier(for processObjectID: AudioObjectID) -> String? {
        guard let bundleID = try? CoreAudioProperty.string(
            processObjectID,
            CoreAudioProperty.address(kAudioProcessPropertyBundleID)
        ) else {
            return nil
        }
        return bundleID.isEmpty ? nil : bundleID
    }

    private static func isRunningOutput(_ processObjectID: AudioObjectID) -> Bool {
        let value = (try? CoreAudioProperty.value(
            processObjectID,
            CoreAudioProperty.address(kAudioProcessPropertyIsRunningOutput),
            default: UInt32(0)
        )) ?? 0
        return value != 0
    }
}

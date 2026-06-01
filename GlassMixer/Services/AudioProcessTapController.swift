import CoreAudio
import Foundation
import OSLog

/// Real per-app volume engine built on **Core Audio Process Taps** (macOS 14.4+).
///
/// macOS exposes no public API to set another app's output volume directly. The supported,
/// Apple-sanctioned mechanism — which supersedes shipping a third-party HAL virtual driver — is:
///
/// 1. For each controllable process, create a *muted* process tap
///    (`CATapDescription` + `AudioHardwareCreateProcessTap`). Muting routes the app's audio to us
///    instead of the speakers.
/// 2. Combine every tap into one **private aggregate device** bound to the chosen output device
///    (`AudioHardwareCreateAggregateDevice`, `kAudioAggregateDeviceTapListKey`).
/// 3. Install an IOProc on the aggregate that multiplies each app's tapped samples by that app's
///    gain (0…1.5), mixes them, computes real peak/RMS, and renders to the output device.
///
/// The result is genuine, independent per-app volume plus real meters, entirely in user space.
///
/// > Note: tap creation triggers the macOS "audio recording" permission prompt and requires
/// > `NSAudioCaptureUsageDescription` + the `com.apple.security.device.audio-input` entitlement.
/// > This is realtime Core Audio C-interop; it must be validated on-device (macOS 26 / Xcode 26).
@available(macOS 14.4, *)
actor AudioProcessTapController {
    private let log = Logger(subsystem: "com.example.louddd", category: "TapEngine")

    /// Shared, lock-guarded mixing state read from the realtime IOProc.
    private let mix = TapMixState()

    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var taps: [AudioApp.ID: TapHandle] = [:]
    private var outputDeviceUID: String?
    private var running = false

    struct TapHandle {
        let appID: AudioApp.ID
        let pid: pid_t
        let tapObjectID: AudioObjectID
        let uuid: String
        let channelCount: Int
    }

    // MARK: - Permission

    /// Whether the process currently holds audio-recording (tap) permission.
    /// Creating the first tap is what actually triggers the system prompt.
    static func hasPermission() -> Bool {
        // A zero-process global tap is the cheapest probe; success implies permission was granted.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var probeID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &probeID)
        if status == noErr, probeID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(probeID)
            return true
        }
        return false
    }

    // MARK: - Lifecycle

    func start(outputDeviceUID: String?) {
        self.outputDeviceUID = outputDeviceUID
        running = true
    }

    func stop() {
        teardownAggregate()
        for handle in taps.values {
            AudioHardwareDestroyProcessTap(handle.tapObjectID)
        }
        taps.removeAll()
        running = false
    }

    func updateOutputDevice(uid: String?) {
        guard uid != outputDeviceUID else { return }
        outputDeviceUID = uid
        rebuildAggregateIfNeeded()
    }

    // MARK: - Gain & mute (called from the main-actor service)

    func setGain(_ gain: Double, for appID: AudioApp.ID) {
        mix.setGain(Float(min(max(gain, 0), 1.5)), for: appID)
    }

    func setMuted(_ muted: Bool, for appID: AudioApp.ID) {
        mix.setMuted(muted, for: appID)
    }

    /// Snapshot of live metering keyed by app id: (peak, rms), both 0…1.
    func meters() -> [AudioApp.ID: (peak: Double, rms: Double)] {
        mix.meterSnapshot()
    }

    // MARK: - Tap set reconciliation

    /// Ensure exactly the supplied apps have active taps, then rebuild the aggregate render graph.
    /// Returns the set of app ids the engine is actually controlling.
    func reconcile(controllableApps apps: [AudioApp]) -> Set<AudioApp.ID> {
        guard running else { return [] }

        let desired = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0.processID) })

        // Remove taps for apps that are gone.
        for (appID, handle) in taps where desired[appID] == nil {
            AudioHardwareDestroyProcessTap(handle.tapObjectID)
            taps[appID] = nil
            mix.remove(appID: appID)
        }

        // Create taps for newly audible apps.
        var changed = false
        for (appID, pid) in desired where taps[appID] == nil {
            if let handle = createTap(appID: appID, pid: pid) {
                taps[appID] = handle
                mix.ensure(appID: appID)
                changed = true
            }
        }

        if changed || aggregateDeviceID == kAudioObjectUnknown {
            rebuildAggregateIfNeeded()
        }

        return Set(taps.keys)
    }

    // MARK: - Tap creation

    private func createTap(appID: AudioApp.ID, pid: pid_t) -> TapHandle? {
        guard let processObjectID = Self.processObject(for: pid) else { return nil }

        let description = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        description.name = "louddd-tap-\(pid)"
        description.isPrivate = true
        // Mute the app's normal output so our engine becomes the sole render path for it.
        description.muteBehavior = .mutedWhenTapped

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr, tapID != kAudioObjectUnknown else {
            log.error("AudioHardwareCreateProcessTap failed for pid \(pid): \(status)")
            return nil
        }

        let channels = tapChannelCount(tapID)
        return TapHandle(
            appID: appID,
            pid: pid,
            tapObjectID: tapID,
            uuid: description.uuid.uuidString,
            channelCount: channels
        )
    }

    private func tapChannelCount(_ tapID: AudioObjectID) -> Int {
        var address = CoreAudioProperty.address(kAudioTapPropertyFormat)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd) == noErr else { return 2 }
        return Int(asbd.mChannelsPerFrame == 0 ? 2 : asbd.mChannelsPerFrame)
    }

    private static func processObject(for pid: pid_t) -> AudioObjectID? {
        var address = CoreAudioProperty.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var inputPID = pid
        var processID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            CoreAudioProperty.systemObject,
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &inputPID,
            &size,
            &processID
        )
        guard status == noErr, processID != kAudioObjectUnknown else { return nil }
        return processID
    }

    // MARK: - Aggregate device + IOProc

    private func rebuildAggregateIfNeeded() {
        teardownAggregate()
        guard running, !taps.isEmpty else { return }

        let aggregateUID = "com.example.louddd.aggregate.\(UUID().uuidString)"
        let tapList: [[String: Any]] = taps.values.map { handle in
            [
                kAudioSubTapUIDKey as String: handle.uuid,
                kAudioSubTapDriftCompensationKey as String: 0
            ]
        }

        var description: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "louddd Mixer",
            kAudioAggregateDeviceUIDKey as String: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey as String: 1,
            kAudioAggregateDeviceIsStackedKey as String: 0,
            kAudioAggregateDeviceTapListKey as String: tapList
        ]

        if let outputDeviceUID {
            description[kAudioAggregateDeviceMainSubDeviceKey as String] = outputDeviceUID
            description[kAudioAggregateDeviceSubDeviceListKey as String] = [
                [kAudioSubDeviceUIDKey as String: outputDeviceUID]
            ]
        }

        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        let createStatus = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard createStatus == noErr, aggregateID != kAudioObjectUnknown else {
            log.error("AudioHardwareCreateAggregateDevice failed: \(createStatus)")
            return
        }
        aggregateDeviceID = aggregateID

        // Channel layout: taps are concatenated on the aggregate input in tap-list order.
        let segments = buildSegments()
        mix.setLayout(segments)

        installIOProc(on: aggregateID)
    }

    private func buildSegments() -> [TapMixState.Segment] {
        var offset = 0
        var segments: [TapMixState.Segment] = []
        for handle in taps.values {
            segments.append(
                TapMixState.Segment(
                    appID: handle.appID,
                    startChannel: offset,
                    channelCount: handle.channelCount
                )
            )
            offset += handle.channelCount
        }
        return segments
    }

    private func installIOProc(on deviceID: AudioObjectID) {
        let mix = self.mix
        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, nil) { _, inInputData, _, outOutputData, _ in
            mix.render(input: inInputData, output: outOutputData)
        }
        guard status == noErr, let procID else {
            log.error("AudioDeviceCreateIOProcIDWithBlock failed: \(status)")
            return
        }
        ioProcID = procID

        let startStatus = AudioDeviceStart(deviceID, procID)
        if startStatus != noErr {
            log.error("AudioDeviceStart failed: \(startStatus)")
        }
    }

    private func teardownAggregate() {
        if aggregateDeviceID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateDeviceID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }
        ioProcID = nil
        aggregateDeviceID = kAudioObjectUnknown
    }
}

/// Lock-guarded state shared between the audio-control actor and the realtime IOProc.
///
/// The IOProc briefly takes an `os_unfair_lock`. For a production realtime path this should move
/// to lock-free atomics / a triple buffer; it is kept simple here and flagged for on-device tuning.
@available(macOS 14.4, *)
final class TapMixState: @unchecked Sendable {
    struct Segment {
        let appID: AudioApp.ID
        let startChannel: Int
        let channelCount: Int
    }

    private var lock = os_unfair_lock()
    private var gains: [AudioApp.ID: Float] = [:]
    private var muted: Set<AudioApp.ID> = []
    private var layout: [Segment] = []
    private var peaks: [AudioApp.ID: Float] = [:]
    private var rms: [AudioApp.ID: Float] = [:]

    func setGain(_ gain: Float, for appID: AudioApp.ID) {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        gains[appID] = gain
    }

    func setMuted(_ isMuted: Bool, for appID: AudioApp.ID) {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        if isMuted { muted.insert(appID) } else { muted.remove(appID) }
    }

    func ensure(appID: AudioApp.ID) {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        if gains[appID] == nil { gains[appID] = 1 }
    }

    func remove(appID: AudioApp.ID) {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        gains[appID] = nil
        muted.remove(appID)
        peaks[appID] = nil
        rms[appID] = nil
    }

    func setLayout(_ layout: [Segment]) {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        self.layout = layout
    }

    func meterSnapshot() -> [AudioApp.ID: (peak: Double, rms: Double)] {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        var result: [AudioApp.ID: (peak: Double, rms: Double)] = [:]
        for (appID, peak) in peaks {
            result[appID] = (Double(peak), Double(rms[appID] ?? 0))
        }
        return result
    }

    /// Realtime mix callback: apply per-app gain to tapped inputs, sum into the output, and meter.
    func render(
        input: UnsafePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>
    ) {
        let inputChannels = Self.channelPointers(input)
        let outputChannels = Self.channelPointers(UnsafePointer(output))
        guard !outputChannels.isEmpty else { return }

        let frames = outputChannels[0].count
        for channel in outputChannels {
            for frame in 0..<min(frames, channel.count) {
                channel.ptr[frame * channel.stride] = 0
            }
        }

        os_unfair_lock_lock(&lock)
        let layout = self.layout
        let gains = self.gains
        let muted = self.muted
        os_unfair_lock_unlock(&lock)

        var localPeaks: [AudioApp.ID: Float] = [:]
        var localRMS: [AudioApp.ID: Float] = [:]

        for segment in layout {
            let gain = muted.contains(segment.appID) ? 0 : (gains[segment.appID] ?? 1)
            var peak: Float = 0
            var sumSquares: Float = 0
            var sampleCount: Float = 0

            for offset in 0..<segment.channelCount {
                let inIndex = segment.startChannel + offset
                guard inIndex < inputChannels.count else { continue }
                let source = inputChannels[inIndex]
                let destination = outputChannels[offset % outputChannels.count]
                let n = min(frames, source.count, destination.count)

                for frame in 0..<n {
                    let sample = source.ptr[frame * source.stride]
                    destination.ptr[frame * destination.stride] += sample * gain
                    let magnitude = abs(sample)
                    if magnitude > peak { peak = magnitude }
                    sumSquares += sample * sample
                    sampleCount += 1
                }
            }

            localPeaks[segment.appID] = peak
            localRMS[segment.appID] = sampleCount > 0 ? (sumSquares / sampleCount).squareRoot() : 0
        }

        os_unfair_lock_lock(&lock)
        peaks = localPeaks
        rms = localRMS
        os_unfair_lock_unlock(&lock)
    }

    private struct ChannelBuffer {
        let ptr: UnsafeMutablePointer<Float>
        /// Number of frames addressable through this channel view.
        let count: Int
        /// Element stride between consecutive frames (1 for non-interleaved, channel count for interleaved).
        let stride: Int
    }

    /// Flattens an AudioBufferList into per-channel Float pointers, handling both interleaved and
    /// non-interleaved Float32 layouts (taps deliver Float32). Interleaved channels are exposed as
    /// strided views over shared storage rather than copied.
    private static func channelPointers(_ list: UnsafePointer<AudioBufferList>) -> [ChannelBuffer] {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        var channels: [ChannelBuffer] = []

        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let channelsInBuffer = max(1, Int(buffer.mNumberChannels))
            let floatPtr = data.assumingMemoryBound(to: Float.self)
            let totalFloats = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let framesPerChannel = totalFloats / channelsInBuffer

            if channelsInBuffer == 1 {
                channels.append(ChannelBuffer(ptr: floatPtr, count: totalFloats, stride: 1))
            } else {
                for channel in 0..<channelsInBuffer {
                    channels.append(
                        ChannelBuffer(
                            ptr: floatPtr.advanced(by: channel),
                            count: framesPerChannel,
                            stride: channelsInBuffer
                        )
                    )
                }
            }
        }
        return channels
    }
}

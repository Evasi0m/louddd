import CoreAudio
import Foundation

#if canImport(IOBluetooth)
import IOBluetooth
#endif

/// Enumerates output-capable audio devices, watches for hardware changes, and provides the
/// public, fully supported controls macOS exposes: switching the default output device and
/// reading/writing a device's hardware master volume + mute. Also surfaces transport type
/// (Bluetooth / USB / built-in …) and best-effort Bluetooth battery for the device picker.
///
/// This consolidates what used to be `AudioDeviceObserver` and adds device-list enumeration,
/// switching, and per-device volume control.
final class OutputDeviceManager: @unchecked Sendable {
    private let queue = DispatchQueue(label: "louddd.OutputDeviceManager")
    private var listenersInstalled = false
    private var onChange: (@Sendable () -> Void)?

    private let deviceListAddress = CoreAudioProperty.address(kAudioHardwarePropertyDevices)
    private let defaultOutputAddress = CoreAudioProperty.address(kAudioHardwarePropertyDefaultOutputDevice)

    // MARK: - Lifecycle

    func start(onChange: @escaping @Sendable () -> Void) {
        guard !listenersInstalled else { return }
        listenersInstalled = true
        self.onChange = onChange

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.onChange?()
        }

        var deviceList = deviceListAddress
        AudioObjectAddPropertyListenerBlock(CoreAudioProperty.systemObject, &deviceList, queue, block)

        var defaultOutput = defaultOutputAddress
        AudioObjectAddPropertyListenerBlock(CoreAudioProperty.systemObject, &defaultOutput, queue, block)
    }

    // MARK: - Enumeration

    /// All output-capable devices, with the current default flagged.
    func outputDevices() -> [AudioDevice] {
        let defaultID = currentDefaultOutputID()
        let allIDs = (try? CoreAudioProperty.array(
            CoreAudioProperty.systemObject,
            deviceListAddress,
            of: AudioObjectID.self
        )) ?? []

        return allIDs.compactMap { id in
            guard outputChannelCount(for: id) > 0 else { return nil }
            return makeDevice(id: id, isDefault: id == defaultID)
        }
    }

    func currentDefaultOutputDevice() -> AudioDevice? {
        let id = currentDefaultOutputID()
        guard id != kAudioObjectUnknown else { return nil }
        return makeDevice(id: id, isDefault: true)
    }

    private func currentDefaultOutputID() -> AudioObjectID {
        (try? CoreAudioProperty.value(
            CoreAudioProperty.systemObject,
            defaultOutputAddress,
            default: AudioObjectID(kAudioObjectUnknown)
        )) ?? kAudioObjectUnknown
    }

    private func makeDevice(id: AudioObjectID, isDefault: Bool) -> AudioDevice {
        let transport = transport(for: id)
        return AudioDevice(
            id: id,
            uid: uid(for: id) ?? "",
            name: name(for: id) ?? transport.label,
            isDefaultOutput: isDefault,
            transport: transport,
            volume: volume(for: id),
            isMuted: isMuted(for: id),
            batteryPercent: transport.isBluetooth ? batteryPercent(for: id) : nil
        )
    }

    // MARK: - Switching & control (public, supported APIs)

    func setDefaultOutputDevice(_ deviceID: AudioObjectID) throws {
        try CoreAudioProperty.setValue(
            CoreAudioProperty.systemObject,
            defaultOutputAddress,
            value: deviceID
        )
    }

    func setVolume(_ volume: Double, for deviceID: AudioObjectID) throws {
        let clamped = Float(min(max(volume, 0), 1))
        let address = CoreAudioProperty.address(
            kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        )

        // Master element first; fall back to writing each channel when only per-channel controls exist.
        if CoreAudioProperty.isSettable(deviceID, address) {
            try CoreAudioProperty.setValue(deviceID, address, value: clamped)
            return
        }

        var wroteAny = false
        for channel in UInt32(1)...UInt32(2) {
            let channelAddress = CoreAudioProperty.address(
                kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeOutput,
                element: channel
            )
            if CoreAudioProperty.isSettable(deviceID, channelAddress) {
                try? CoreAudioProperty.setValue(deviceID, channelAddress, value: clamped)
                wroteAny = true
            }
        }
        if !wroteAny { throw CoreAudioError.osStatus(kAudioHardwareUnsupportedOperationError) }
    }

    func setMute(_ muted: Bool, for deviceID: AudioObjectID) throws {
        let address = CoreAudioProperty.address(
            kAudioDevicePropertyMute,
            scope: kAudioObjectPropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        )
        guard CoreAudioProperty.isSettable(deviceID, address) else {
            throw CoreAudioError.osStatus(kAudioHardwareUnsupportedOperationError)
        }
        try CoreAudioProperty.setValue(deviceID, address, value: UInt32(muted ? 1 : 0))
    }

    // MARK: - Device property readers

    private func outputChannelCount(for id: AudioObjectID) -> Int {
        var address = CoreAudioProperty.address(
            kAudioDevicePropertyStreamConfiguration,
            scope: kAudioObjectPropertyScopeOutput
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else {
            return 0
        }

        let bufferList = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferList.deallocate() }

        guard AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, bufferList) == noErr else {
            return 0
        }

        let list = UnsafeMutableAudioBufferListPointer(bufferList.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func name(for id: AudioObjectID) -> String? {
        try? CoreAudioProperty.string(id, CoreAudioProperty.address(kAudioObjectPropertyName))
    }

    private func uid(for id: AudioObjectID) -> String? {
        try? CoreAudioProperty.string(id, CoreAudioProperty.address(kAudioDevicePropertyDeviceUID))
    }

    private func transport(for id: AudioObjectID) -> AudioDeviceTransport {
        let raw = (try? CoreAudioProperty.value(
            id,
            CoreAudioProperty.address(kAudioDevicePropertyTransportType),
            default: UInt32(0)
        )) ?? 0
        return AudioDeviceTransport(rawTransport: raw)
    }

    private func volume(for id: AudioObjectID) -> Double? {
        for element in [kAudioObjectPropertyElementMain, AudioObjectPropertyElement(1)] {
            let address = CoreAudioProperty.address(
                kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeOutput,
                element: element
            )
            guard CoreAudioProperty.hasProperty(id, address),
                  let scalar = try? CoreAudioProperty.value(id, address, default: Float(0)) else {
                continue
            }
            return Double(scalar)
        }
        return nil
    }

    private func isMuted(for id: AudioObjectID) -> Bool {
        let address = CoreAudioProperty.address(
            kAudioDevicePropertyMute,
            scope: kAudioObjectPropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        )
        guard CoreAudioProperty.hasProperty(id, address),
              let value = try? CoreAudioProperty.value(id, address, default: UInt32(0)) else {
            return false
        }
        return value != 0
    }

    /// Best-effort Bluetooth battery for a Core Audio device, matched to a paired device by name.
    private func batteryPercent(for id: AudioObjectID) -> Int? {
        #if canImport(IOBluetooth)
        guard let deviceName = name(for: id),
              let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return nil
        }
        let match = paired.first { device in
            guard let bluetoothName = device.name else { return false }
            return deviceName.localizedCaseInsensitiveContains(bluetoothName)
                || bluetoothName.localizedCaseInsensitiveContains(deviceName)
        }
        // `batteryPercentCombined` is a 0…1 fraction on supported devices; nil/0 means unknown.
        if let value = match?.value(forKey: "batteryPercentCombined") as? NSNumber, value.doubleValue > 0 {
            return Int((value.doubleValue * 100).rounded())
        }
        #endif
        return nil
    }
}

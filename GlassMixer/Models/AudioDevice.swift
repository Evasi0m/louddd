import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable, Sendable {
    let id: AudioObjectID
    /// Stable Core Audio device UID, used for aggregate-device composition and persistence.
    var uid: String
    var name: String
    var isDefaultOutput: Bool
    var transport: AudioDeviceTransport
    /// Hardware master volume (0…1) when the device exposes a scalar volume control, otherwise nil.
    var volume: Double?
    var isMuted: Bool
    /// Best-effort Bluetooth battery percentage (0…100); nil when unavailable.
    var batteryPercent: Int?

    init(
        id: AudioObjectID,
        uid: String = "",
        name: String,
        isDefaultOutput: Bool,
        transport: AudioDeviceTransport = .unknown,
        volume: Double? = nil,
        isMuted: Bool = false,
        batteryPercent: Int? = nil
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.isDefaultOutput = isDefaultOutput
        self.transport = transport
        self.volume = volume
        self.isMuted = isMuted
        self.batteryPercent = batteryPercent
    }

    /// True when the device exposes a hardware volume scalar we can drive.
    var canControlVolume: Bool {
        volume != nil
    }
}

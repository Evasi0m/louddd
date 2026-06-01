import CoreAudio
import Foundation

/// High-level classification of an audio device's physical connection, derived from
/// `kAudioDevicePropertyTransportType`. Drives the icon + label shown in the device picker.
enum AudioDeviceTransport: String, Hashable, Sendable, Codable {
    case builtIn
    case bluetooth
    case bluetoothLE
    case usb
    case airPlay
    case hdmi
    case displayPort
    case thunderbolt
    case aggregate
    case virtual
    case unknown

    init(rawTransport: UInt32) {
        switch rawTransport {
        case kAudioDeviceTransportTypeBuiltIn:
            self = .builtIn
        case kAudioDeviceTransportTypeBluetooth:
            self = .bluetooth
        case kAudioDeviceTransportTypeBluetoothLE:
            self = .bluetoothLE
        case kAudioDeviceTransportTypeUSB:
            self = .usb
        case kAudioDeviceTransportTypeAirPlay:
            self = .airPlay
        case kAudioDeviceTransportTypeHDMI:
            self = .hdmi
        case kAudioDeviceTransportTypeDisplayPort:
            self = .displayPort
        case kAudioDeviceTransportTypeThunderbolt:
            self = .thunderbolt
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate:
            self = .aggregate
        case kAudioDeviceTransportTypeVirtual:
            self = .virtual
        default:
            self = .unknown
        }
    }

    /// True for any wireless device where battery / connection state matters.
    var isBluetooth: Bool {
        self == .bluetooth || self == .bluetoothLE
    }

    /// SF Symbol used in the device picker.
    var iconName: String {
        switch self {
        case .builtIn:
            return "laptopcomputer"
        case .bluetooth, .bluetoothLE:
            return "airpodspro"
        case .usb:
            return "cable.connector"
        case .airPlay:
            return "airplayaudio"
        case .hdmi, .displayPort:
            return "display"
        case .thunderbolt:
            return "bolt.horizontal"
        case .aggregate:
            return "rectangle.3.group"
        case .virtual:
            return "waveform.badge.magnifyingglass"
        case .unknown:
            return "hifispeaker"
        }
    }

    var label: String {
        switch self {
        case .builtIn:
            return "Built-in"
        case .bluetooth:
            return "Bluetooth"
        case .bluetoothLE:
            return "Bluetooth LE"
        case .usb:
            return "USB"
        case .airPlay:
            return "AirPlay"
        case .hdmi:
            return "HDMI"
        case .displayPort:
            return "DisplayPort"
        case .thunderbolt:
            return "Thunderbolt"
        case .aggregate:
            return "Aggregate"
        case .virtual:
            return "Virtual"
        case .unknown:
            return "Output"
        }
    }
}

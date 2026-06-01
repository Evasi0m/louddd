import Foundation

protocol AudioBackend: Sendable {
    /// Apps currently producing output audio, with live volume/meter state.
    var appUpdates: AsyncStream<[AudioApp]> { get }
    /// The current default output device (nil when none).
    var deviceUpdates: AsyncStream<AudioDevice?> { get }
    /// The full list of selectable output devices.
    var deviceListUpdates: AsyncStream<[AudioDevice]> { get }

    func start() async throws
    func stop() async

    // Per-app mixing
    func setVolume(_ volume: Double, for appID: AudioApp.ID) async throws
    func setMute(_ muted: Bool, for appID: AudioApp.ID) async throws
    func setFocusProfile(_ profile: FocusProfile) async throws

    // Output device control
    func setDefaultOutputDevice(_ deviceID: AudioDevice.ID) async throws
    func setDeviceVolume(_ volume: Double, for deviceID: AudioDevice.ID) async throws
    func setDeviceMute(_ muted: Bool, for deviceID: AudioDevice.ID) async throws
}

enum AudioBackendError: LocalizedError {
    case driverUnavailable
    case appSessionMissing
    case invalidVolume
    case permissionDenied
    case deviceUnavailable
    case commandRejected(String)

    var errorDescription: String? {
        switch self {
        case .driverUnavailable:
            return "The per-app audio engine is not available on this Mac."
        case .appSessionMissing:
            return "The selected app audio session is no longer active."
        case .invalidVolume:
            return "Volume must be between 0.0 and 1.5."
        case .permissionDenied:
            return "louddd! needs audio-recording permission to control per-app volume."
        case .deviceUnavailable:
            return "The selected output device is no longer available."
        case .commandRejected(let message):
            return message
        }
    }
}

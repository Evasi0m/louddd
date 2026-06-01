import Foundation

protocol AudioBackend: Sendable {
    var appUpdates: AsyncStream<[AudioApp]> { get }
    var deviceUpdates: AsyncStream<AudioDevice?> { get }

    func start() async throws
    func stop() async
    func setVolume(_ volume: Double, for appID: AudioApp.ID) async throws
    func setFocusProfile(_ profile: FocusProfile) async throws
}

enum AudioBackendError: LocalizedError {
    case driverUnavailable
    case appSessionMissing
    case invalidVolume
    case commandRejected(String)

    var errorDescription: String? {
        switch self {
        case .driverUnavailable:
            return "The virtual audio driver is not installed or not reachable."
        case .appSessionMissing:
            return "The selected app audio session is no longer active."
        case .invalidVolume:
            return "Volume must be between 0.0 and 1.5."
        case .commandRejected(let message):
            return message
        }
    }
}

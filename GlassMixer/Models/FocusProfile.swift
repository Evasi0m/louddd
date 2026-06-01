import Foundation

struct FocusProfile: Hashable, Codable, Sendable {
    var isEnabled: Bool = true
    var faceTimeVolume: Double = 1.0
    var movieAppDefaultVolume: Double = 0.55
    var manuallyBypassedAppIDs: Set<String> = []

    func shouldBypass(appID: String) -> Bool {
        manuallyBypassedAppIDs.contains(appID)
    }
}

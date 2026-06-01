import AppKit
import Foundation

struct AudioApp: Identifiable, Hashable, Sendable {
    let id: String
    var processID: pid_t
    var bundleIdentifier: String?
    var displayName: String
    var iconPathHint: String?
    var volume: Double
    var isMixable: Bool
    var canControlVolume: Bool
    var isAudible: Bool
    var peakLevel: Double
    var rmsLevel: Double
    var isFaceTimeCandidate: Bool

    var clampedVolume: Double {
        min(max(volume, 0), 1.5)
    }

    static func identity(processID: pid_t, bundleIdentifier: String?) -> String {
        if let bundleIdentifier {
            return "\(bundleIdentifier)#\(processID)"
        }
        return "pid#\(processID)"
    }
}

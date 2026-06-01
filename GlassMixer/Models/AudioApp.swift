import AppKit
import Foundation

struct AudioApp: Identifiable, Hashable, Sendable {
    let id: String
    var processID: pid_t
    var bundleIdentifier: String?
    var displayName: String
    var iconPathHint: String?
    var volume: Double
    var isMuted: Bool
    var isMixable: Bool
    var canControlVolume: Bool
    var isAudible: Bool
    var peakLevel: Double
    var rmsLevel: Double
    var isFaceTimeCandidate: Bool

    init(
        id: String,
        processID: pid_t,
        bundleIdentifier: String?,
        displayName: String,
        iconPathHint: String? = nil,
        volume: Double = 1,
        isMuted: Bool = false,
        isMixable: Bool = true,
        canControlVolume: Bool = false,
        isAudible: Bool = true,
        peakLevel: Double = 0,
        rmsLevel: Double = 0,
        isFaceTimeCandidate: Bool = false
    ) {
        self.id = id
        self.processID = processID
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.iconPathHint = iconPathHint
        self.volume = volume
        self.isMuted = isMuted
        self.isMixable = isMixable
        self.canControlVolume = canControlVolume
        self.isAudible = isAudible
        self.peakLevel = peakLevel
        self.rmsLevel = rmsLevel
        self.isFaceTimeCandidate = isFaceTimeCandidate
    }

    var clampedVolume: Double {
        min(max(volume, 0), 1.5)
    }

    /// Effective gain after accounting for mute, used by the render engine.
    var effectiveGain: Double {
        isMuted ? 0 : clampedVolume
    }

    static func identity(processID: pid_t, bundleIdentifier: String?) -> String {
        if let bundleIdentifier {
            return "\(bundleIdentifier)#\(processID)"
        }
        return "pid#\(processID)"
    }
}

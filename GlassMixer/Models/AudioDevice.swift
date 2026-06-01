import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable, Sendable {
    let id: AudioObjectID
    var name: String
    var isDefaultOutput: Bool
}

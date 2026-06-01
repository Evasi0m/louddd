import CoreAudio
import Foundation

/// Thin, throwing wrappers around the `AudioObjectGetPropertyData` / `AudioObjectSetPropertyData`
/// C API so the rest of the codebase can read and write Core Audio properties without repeating
/// size-probing and pointer boilerplate.
enum CoreAudioProperty {
    static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func hasProperty(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return AudioObjectHasProperty(object, &address)
    }

    static func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(object, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    /// Reads a fixed-size scalar property (e.g. `UInt32`, `Float32`, `AudioObjectID`).
    static func value<T>(
        _ object: AudioObjectID,
        _ address: AudioObjectPropertyAddress,
        default defaultValue: T
    ) throws -> T {
        var address = address
        var value = defaultValue
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, UnsafeMutableRawPointer(pointer))
        }
        guard status == noErr else { throw CoreAudioError.osStatus(status) }
        return value
    }

    /// Reads a variable-length array property (e.g. the device list, a stream configuration).
    static func array<T>(
        _ object: AudioObjectID,
        _ address: AudioObjectPropertyAddress,
        of type: T.Type
    ) throws -> [T] {
        var address = address
        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(object, &address, 0, nil, &dataSize)
        guard sizeStatus == noErr else { throw CoreAudioError.osStatus(sizeStatus) }
        guard dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<T>.stride
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<T>.alignment
        )
        defer { buffer.deallocate() }

        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &dataSize, buffer)
        guard status == noErr else { throw CoreAudioError.osStatus(status) }
        let typed = buffer.bindMemory(to: T.self, capacity: count)
        return Array(UnsafeBufferPointer(start: typed, count: count))
    }

    static func string(
        _ object: AudioObjectID,
        _ address: AudioObjectPropertyAddress
    ) throws -> String {
        var address = address
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, UnsafeMutableRawPointer(pointer))
        }
        guard status == noErr, let value else { throw CoreAudioError.osStatus(status) }
        return value.takeRetainedValue() as String
    }

    static func setValue<T>(
        _ object: AudioObjectID,
        _ address: AudioObjectPropertyAddress,
        value: T
    ) throws {
        var address = address
        let size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafePointer(to: value) { pointer in
            AudioObjectSetPropertyData(object, &address, 0, nil, size, UnsafeRawPointer(pointer))
        }
        guard status == noErr else { throw CoreAudioError.osStatus(status) }
    }
}

enum CoreAudioError: LocalizedError {
    case osStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .osStatus(let status):
            return "Core Audio error (OSStatus \(status))"
        }
    }
}

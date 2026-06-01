import Foundation

/// Lightweight persistence for per-app mix settings and the last chosen output device.
///
/// Per-app values are keyed by **bundle identifier** (stable across launches) rather than the
/// runtime `AudioApp.id`, which embeds a PID that changes each launch.
struct PreferencesStore {
    private let defaults: UserDefaults

    private enum Key {
        static let appVolumes = "louddd.appVolumes"
        static let appMutes = "louddd.appMutes"
        static let lastOutputDeviceUID = "louddd.lastOutputDeviceUID"
        static let focusEnabled = "louddd.focusEnabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Per-app volume

    var appVolumes: [String: Double] {
        get { (defaults.dictionary(forKey: Key.appVolumes) as? [String: Double]) ?? [:] }
        nonmutating set { defaults.set(newValue, forKey: Key.appVolumes) }
    }

    func volume(forBundleID bundleID: String) -> Double? {
        appVolumes[bundleID]
    }

    func setVolume(_ volume: Double, forBundleID bundleID: String) {
        var values = appVolumes
        values[bundleID] = volume
        appVolumes = values
    }

    // MARK: Per-app mute

    var appMutes: [String: Bool] {
        get { (defaults.dictionary(forKey: Key.appMutes) as? [String: Bool]) ?? [:] }
        nonmutating set { defaults.set(newValue, forKey: Key.appMutes) }
    }

    func isMuted(forBundleID bundleID: String) -> Bool {
        appMutes[bundleID] ?? false
    }

    func setMuted(_ muted: Bool, forBundleID bundleID: String) {
        var values = appMutes
        values[bundleID] = muted
        appMutes = values
    }

    // MARK: Output device

    var lastOutputDeviceUID: String? {
        get { defaults.string(forKey: Key.lastOutputDeviceUID) }
        nonmutating set { defaults.set(newValue, forKey: Key.lastOutputDeviceUID) }
    }

    // MARK: Focus

    var focusEnabled: Bool {
        get { defaults.object(forKey: Key.focusEnabled) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.focusEnabled) }
    }
}

import AppKit
import Darwin

enum AppIconResolver {
    // Cache resolved icons so SwiftUI gets a stable NSImage instance each render instead of a freshly
    // decoded one every poll, which caused the icon to flicker.
    private static var cache: [String: NSImage] = [:]

    /// Resolve an app icon, preferring a bundle-id lookup and falling back to a known bundle path.
    static func icon(for bundleIdentifier: String?, iconPath: String? = nil) -> NSImage? {
        let key = bundleIdentifier ?? iconPath
        if let key, let cached = cache[key] {
            return cached
        }

        var image: NSImage?
        if let bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else if let iconPath {
            image = NSWorkspace.shared.icon(forFile: iconPath)
        }

        if let key, let image {
            cache[key] = image
        }
        return image
    }
}

/// Resolves the user-facing application that owns an audio process.
///
/// Audio frequently comes from helper processes (e.g. "Google Chrome Helper (Renderer)"), whose
/// bundle id can't be resolved to an app icon and whose name is just "helper". We walk up the parent
/// process chain to find the real owning app so its proper name and icon are shown instead.
enum ProcessAppResolver {
    static func owningApplication(pid: pid_t) -> NSRunningApplication? {
        var current = pid
        var fallback: NSRunningApplication? = NSRunningApplication(processIdentifier: pid)

        for _ in 0..<8 {
            if let app = NSRunningApplication(processIdentifier: current) {
                // A regular (Dock-visible) app with a bundle is the real owner.
                if app.activationPolicy == .regular, app.bundleURL != nil {
                    return app
                }
                if fallback?.bundleIdentifier == nil, app.bundleIdentifier != nil {
                    fallback = app
                }
            }
            guard let parent = parentPID(of: current), parent > 1, parent != current else { break }
            current = parent
        }
        return fallback
    }

    static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let status = sysctl(&mib, 4, &info, &size, nil, 0)
        guard status == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}

import AppKit

enum AppIconResolver {
    static func icon(for bundleIdentifier: String?) -> NSImage? {
        guard
            let bundleIdentifier,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

import SwiftUI

/// Centralizes adoption of the native macOS 26 **Liquid Glass** APIs (`glassEffect`, `Glass`,
/// `GlassEffectContainer`) with a graceful `.regularMaterial` fallback for earlier systems, so the
/// rest of the UI can request glass surfaces without repeating availability checks.
extension View {
    /// Applies a Liquid Glass surface clipped to a rounded rectangle, falling back to layered
    /// material on systems older than macOS 26.
    @ViewBuilder
    func glassCard(
        cornerRadius: CGFloat = 18,
        interactive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(
                Self.liquidGlass(interactive: interactive, tint: tint),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.regularMaterial)
                    if let tint {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.12))
                    }
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
            }
        }
    }

    /// Assigns a glass identity for fluid morphing inside a `GlassEffectContainer` (no-op pre-26).
    @ViewBuilder
    func glassMorphID(_ id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    @available(macOS 26.0, *)
    private static func liquidGlass(interactive: Bool, tint: Color?) -> Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint)
        }
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }
}

/// Groups multiple glass surfaces so they blend/morph consistently (glass cannot sample glass).
/// Falls back to a plain `VStack` before macOS 26.
struct LiquidGlassGroup<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    init(spacing: CGFloat = 11, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                VStack(spacing: spacing, content: content)
            }
        } else {
            VStack(spacing: spacing, content: content)
        }
    }
}

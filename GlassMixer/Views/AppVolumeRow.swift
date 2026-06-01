import AppKit
import SwiftUI

/// A single app's mixer card. Neutral Liquid Glass surface (no heavy colored tint); state is shown
/// with small, high-contrast accents — a status pill, a clean accent slider, and labelled control
/// chips whose on/off states are always legible (the previous full-red muted card hid its controls).
struct AppVolumeRow: View {
    let app: AudioApp
    let isBypassed: Bool
    let isSoloed: Bool
    let onVolumeChanged: (Double) -> Void
    let onMuteTapped: () -> Void
    let onSoloTapped: () -> Void
    let onBypassTapped: () -> Void

    @State private var localVolume: Double = 1

    var body: some View {
        VStack(spacing: 13) {
            header
            sliderRow
            controlRow
        }
        .padding(14)
        .glassCard(cornerRadius: 20)
        .animation(.snappy(duration: 0.2), value: app.isMuted)
        .animation(.snappy(duration: 0.2), value: isSoloed)
        .onAppear { localVolume = app.clampedVolume }
        .onChange(of: app.volume) { _, newValue in
            guard abs(newValue - localVolume) > 0.015 else { return }
            localVolume = newValue
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 11) {
            appIcon

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(app.displayName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    statusPill
                }

                HStack(spacing: 6) {
                    if app.canControlVolume && !app.isMuted {
                        AudioActivityWaveView(level: app.peakLevel)
                            .frame(width: 28, height: 11)
                    }
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            Text(Formatters.percent(localVolume))
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(app.isMuted ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .contentTransition(.numericText())
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        if app.isMuted {
            StatusPill(text: "Muted", color: .red, systemImage: "speaker.slash.fill")
        } else if !app.canControlVolume {
            StatusPill(text: "Detected", color: .secondary, systemImage: "dot.radiowaves.left.and.right")
        } else if app.peakLevel > 0.04 {
            StatusPill(text: "Live", color: .green, showsDot: true)
        }
    }

    private var subtitle: String {
        if !app.canControlVolume { return "Grant audio permission to control" }
        if app.isMuted { return "Muted" }
        if isSoloed { return "Soloed" }
        return app.isFaceTimeCandidate ? "Voice priority" : "Media stream"
    }

    // MARK: Slider

    private var sliderRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)

            LiquidSlider(
                value: $localVolume,
                range: 0...1.5,
                accent: app.isFaceTimeCandidate ? [.teal, .blue] : [.blue, .indigo]
            ) { value in
                guard app.canControlVolume else { return }
                onVolumeChanged(value)
            }
            .disabled(!app.canControlVolume || app.isMuted)

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Controls

    private var controlRow: some View {
        HStack(spacing: 8) {
            ControlChip(
                systemImage: app.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                label: app.isMuted ? "Unmute" : "Mute",
                isOn: app.isMuted,
                onColor: .red,
                action: onMuteTapped
            )

            ControlChip(
                systemImage: "headphones",
                label: "Solo",
                isOn: isSoloed,
                onColor: .blue,
                action: onSoloTapped
            )

            Spacer(minLength: 0)

            ControlChip(
                systemImage: isBypassed ? "hand.raised.fill" : "wand.and.stars",
                label: isBypassed ? "Manual" : "Auto",
                isOn: isBypassed,
                onColor: .orange,
                action: onBypassTapped
            )
        }
        .disabled(!app.canControlVolume)
        .opacity(app.canControlVolume ? 1 : 0.45)
    }

    // MARK: App icon

    private var appIcon: some View {
        Group {
            if let image = AppIconResolver.icon(for: app.bundleIdentifier, iconPath: app.iconPathHint) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let placeholder = NSImage(named: "AppPlaceholder") {
                // Custom fallback art for apps whose system icon can't be resolved.
                Image(nsImage: placeholder)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 34, height: 34)
        .padding(3)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

/// Small status capsule with a strong, self-contained color so it reads on any background.
private struct StatusPill: View {
    let text: String
    var color: Color
    var systemImage: String? = nil
    var showsDot: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            if showsDot {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .shadow(color: color.opacity(0.7), radius: 3)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .bold))
            }
            Text(text.uppercased())
                .font(.system(size: 8.5, weight: .black, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(color.opacity(0.14), in: Capsule())
    }
}

/// A labelled toggle chip. Off = subtle neutral glass; on = filled accent with white content, so the
/// state is unmistakable (and the action label flips, e.g. Mute → Unmute).
private struct ControlChip: View {
    let systemImage: String
    let label: String
    let isOn: Bool
    let onColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background {
                Capsule()
                    .fill(isOn ? AnyShapeStyle(onColor) : AnyShapeStyle(.white.opacity(0.08)))
            }
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(isOn ? 0 : 0.10), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.15), value: isOn)
    }
}

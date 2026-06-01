import SwiftUI

struct AppVolumeRow: View {
    let app: AudioApp
    let isBypassed: Bool
    let onVolumeChanged: (Double) -> Void
    let onBypassTapped: () -> Void

    @State private var localVolume: Double = 1
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 11) {
            HStack(spacing: 10) {
                appIcon

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(app.displayName)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .lineLimit(1)

                        liveBadge
                    }

                    HStack(spacing: 6) {
                        AudioActivityWaveView(level: app.peakLevel)
                            .frame(width: 34, height: 12)
                        Text(rowSubtitle)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text(Formatters.percent(localVolume))
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(app.canControlVolume ? .primary : .secondary)
                    .contentTransition(.numericText())

                Button(action: onBypassTapped) {
                    Image(systemName: isBypassed ? "hand.raised.fill" : "wand.and.stars")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(isBypassed ? .orange.opacity(0.16) : .white.opacity(0.08), in: Circle())
                        .foregroundStyle(isBypassed ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .help(isBypassed ? "Manual bypass enabled" : "Use Smart Focus")
            }

            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.1.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)

                LiquidSlider(value: $localVolume, range: 0...1.5) { value in
                    guard app.canControlVolume else { return }
                    onVolumeChanged(value)
                }
                .disabled(!app.canControlVolume)
                .opacity(app.canControlVolume ? 1 : 0.45)

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial.opacity(isHovering ? 0.92 : 0.74))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(rowGradient.opacity(isHovering ? 0.18 : 0.10))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(isHovering ? 0.20 : 0.10), lineWidth: 1)
            }
        }
        .scaleEffect(isHovering ? 1.012 : 1)
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isHovering)
        .onAppear {
            localVolume = app.clampedVolume
        }
        .onChange(of: app.volume) { _, newValue in
            guard abs(newValue - localVolume) > 0.015 else { return }
            localVolume = newValue
        }
    }

    private var rowSubtitle: String {
        if !app.canControlVolume {
            return "Detected audio - routing needed"
        }
        return app.isFaceTimeCandidate ? "Voice priority" : "Media stream"
    }

    private var liveBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
                .shadow(color: .green.opacity(0.75), radius: 4)

            Text("LIVE")
                .font(.system(size: 9, weight: .black, design: .rounded))
        }
        .foregroundStyle(.green)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.green.opacity(0.12), in: Capsule())
    }

    private var rowGradient: LinearGradient {
        LinearGradient(
            colors: app.isFaceTimeCandidate
                ? [.green, .cyan, .blue]
                : [.pink, .orange, .yellow],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var appIcon: some View {
        Group {
            if let image = AppIconResolver.icon(for: app.bundleIdentifier) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 36, height: 36)
        .padding(3)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

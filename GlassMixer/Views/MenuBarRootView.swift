import AppKit
import SwiftUI

struct MenuBarRootView: View {
    @Bindable var store: MixerStore
    @Namespace private var rowNamespace

    var body: some View {
        VStack(spacing: 18) {
            header

            if let lastError = store.lastError {
                inlineStatus(lastError)
            }

            if store.apps.isEmpty {
                EmptyAudioStateView()
                    .transition(.blurReplace)
            } else {
                ActiveMixSummaryView(apps: store.apps)

                VStack(spacing: 11) {
                    ForEach(store.apps) { app in
                        AppVolumeRow(
                            app: app,
                            isBypassed: store.focusProfile.shouldBypass(appID: app.id),
                            onVolumeChanged: { volume in
                                store.setVolume(volume, for: app)
                            },
                            onBypassTapped: {
                                store.toggleManualBypass(for: app)
                            }
                        )
                        .matchedGeometryEffect(id: app.id, in: rowNamespace)
                        .transition(.asymmetric(
                            insertion: .push(from: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
                            removal: .push(from: .trailing).combined(with: .opacity)
                        ))
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background { PanelBackgroundView(energy: store.apps.map(\.peakLevel).reduce(0, +)) }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: store.apps)
        .animation(.smooth(duration: 0.24), value: store.focusProfile)
        .task {
            store.start()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [.cyan, .mint, .yellow, .orange, .pink, .cyan],
                            center: .center
                        )
                    )
                    .frame(width: 38, height: 38)
                    .shadow(color: .cyan.opacity(0.28), radius: 14)

                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("louddd!")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(store.outputDeviceName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(.secondary)
                    .background(.secondary.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Quit")

            Button {
                store.toggleFocus()
            } label: {
                ZStack {
                    Circle()
                        .fill(store.focusProfile.isEnabled ? .green.opacity(0.18) : .secondary.opacity(0.12))
                        .frame(width: 32, height: 32)

                    Image(systemName: store.focusProfile.isEnabled ? "person.wave.2.fill" : "person.wave.2")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(store.focusProfile.isEnabled ? .green : .secondary)
                }
            }
            .buttonStyle(.plain)
            .help("Smart Focus")
        }
    }

    private func inlineStatus(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PanelBackgroundView: View {
    let energy: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)

                Canvas { context, size in
                    let energyScale = min(max(energy, 0.2), 2.2)
                    let points = [
                        CGPoint(x: size.width * (0.18 + 0.04 * sin(phase * 0.7)), y: size.height * 0.12),
                        CGPoint(x: size.width * (0.82 + 0.03 * cos(phase * 0.5)), y: size.height * 0.22),
                        CGPoint(x: size.width * (0.56 + 0.05 * sin(phase * 0.4)), y: size.height * 0.92)
                    ]
                    let colors: [Color] = [.cyan.opacity(0.16), .orange.opacity(0.12), .pink.opacity(0.13)]

                    for index in points.indices {
                        let radius = CGFloat(90 + energyScale * 20 + Double(index) * 18)
                        let rect = CGRect(
                            x: points[index].x - radius / 2,
                            y: points[index].y - radius / 2,
                            width: radius,
                            height: radius
                        )
                        context.fill(Path(ellipseIn: rect), with: .color(colors[index]))
                    }
                }
                .blur(radius: 22)
            }
        }
    }
}

private struct ActiveMixSummaryView: View {
    let apps: [AudioApp]

    private var peak: Double {
        min(apps.map(\.peakLevel).max() ?? 0, 1)
    }

    var body: some View {
        HStack(spacing: 10) {
            AudioActivityWaveView(level: peak)
                .frame(width: 54, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(apps.count) active mix\(apps.count == 1 ? "" : "es")")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Text("Only audible controllable apps")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(Formatters.percent(peak))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 1)
        }
    }
}

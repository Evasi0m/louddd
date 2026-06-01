import AppKit
import SwiftUI

struct MenuBarRootView: View {
    @Bindable var store: MixerStore
    @Namespace private var rowNamespace
    @State private var showDevicePicker = false
    @State private var showSettings = false

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

                LiquidGlassGroup(spacing: 11) {
                    ForEach(store.apps) { app in
                        AppVolumeRow(
                            app: app,
                            isBypassed: store.focusProfile.shouldBypass(appID: app.id),
                            isSoloed: store.soloedAppID == app.id,
                            onVolumeChanged: { volume in
                                store.setVolume(volume, for: app)
                            },
                            onMuteTapped: {
                                store.toggleMute(for: app)
                            },
                            onSoloTapped: {
                                store.toggleSolo(for: app)
                            },
                            onBypassTapped: {
                                store.toggleManualBypass(for: app)
                            }
                        )
                        .matchedGeometryEffect(id: app.id, in: rowNamespace)
                        .glassMorphID(app.id, in: rowNamespace)
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
        // Animate only when the set/order of apps changes — not on every 300ms meter update,
        // which otherwise kept the rows (and their icons) springing/jittering continuously.
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: store.apps.map(\.id))
        .animation(.smooth(duration: 0.24), value: store.focusProfile)
        .task {
            store.start()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            logo

            VStack(alignment: .leading, spacing: 2) {
                Text("louddd!")
                    .font(.system(size: 17, weight: .bold, design: .rounded))

                deviceChip
            }

            Spacer()

            focusButton
            settingsButton
            quitButton
        }
    }

    /// Panel logo. Uses the custom `PanelLogo` asset once you add an image; otherwise falls back to
    /// the gradient waveform badge.
    private var logo: some View {
        Group {
            if let custom = NSImage(named: "PanelLogo") {
                Image(nsImage: custom)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [.cyan, .mint, .yellow, .orange, .pink, .cyan],
                                center: .center
                            )
                        )
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(Circle())
        .shadow(color: .cyan.opacity(0.28), radius: 14)
    }

    private var settingsButton: some View {
        Button {
            showSettings.toggle()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(.secondary)
                .glassCard(cornerRadius: 15, interactive: true)
        }
        .buttonStyle(.plain)
        .help("Settings")
        .popover(isPresented: $showSettings, arrowEdge: .bottom) {
            SettingsPopover(store: store)
        }
    }

    /// Tappable chip showing the current output device; opens the Liquid Glass device picker.
    private var deviceChip: some View {
        Button {
            showDevicePicker.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: store.currentOutputDevice?.transport.iconName ?? "hifispeaker")
                    .font(.system(size: 10, weight: .semibold))
                Text(store.outputDeviceName)
                    .font(.system(size: 11))
                    .lineLimit(1)
                if let battery = store.currentOutputDevice?.batteryPercent {
                    Text("· \(battery)%")
                        .font(.system(size: 10, weight: .medium))
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassCard(cornerRadius: 9, interactive: true)
        }
        .buttonStyle(.plain)
        .help("Choose output device")
        .popover(isPresented: $showDevicePicker, arrowEdge: .bottom) {
            OutputDevicePickerView(store: store) {
                showDevicePicker = false
            }
        }
    }

    private var quitButton: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Image(systemName: "power")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(.secondary)
                .glassCard(cornerRadius: 15, interactive: true)
        }
        .buttonStyle(.plain)
        .help("Quit")
    }

    private var focusButton: some View {
        Button {
            store.toggleFocus()
        } label: {
            Image(systemName: store.focusProfile.isEnabled ? "person.wave.2.fill" : "person.wave.2")
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(store.focusProfile.isEnabled ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .frame(width: 32, height: 32)
                .glassCard(cornerRadius: 16, interactive: true, tint: store.focusProfile.isEnabled ? .green : nil)
        }
        .buttonStyle(.plain)
        .help("Smart Focus")
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
                // Energy-reactive color wash sits *behind* the Liquid Glass material so the glass
                // picks it up as a tint without sampling other glass surfaces.
                Canvas { context, size in
                    let energyScale = min(max(energy, 0.2), 2.2)
                    let points = [
                        CGPoint(x: size.width * (0.18 + 0.04 * sin(phase * 0.7)), y: size.height * 0.12),
                        CGPoint(x: size.width * (0.82 + 0.03 * cos(phase * 0.5)), y: size.height * 0.22),
                        CGPoint(x: size.width * (0.56 + 0.05 * sin(phase * 0.4)), y: size.height * 0.92)
                    ]
                    let colors: [Color] = [.cyan.opacity(0.10), .indigo.opacity(0.08), .blue.opacity(0.09)]

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
                .blur(radius: 26)
            }
            .background(panelBase)
        }
    }

    @ViewBuilder
    private var panelBase: some View {
        if #available(macOS 26.0, *) {
            Rectangle().fill(.background.opacity(0.4))
        } else {
            Rectangle().fill(.ultraThinMaterial)
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
        .glassCard(cornerRadius: 16)
    }
}

private struct SettingsPopover: View {
    @Bindable var store: MixerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.system(size: 13, weight: .bold, design: .rounded))

            Toggle(isOn: Binding(
                get: { store.launchesAtLogin },
                set: { store.setLaunchAtLogin($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open at Login")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Start louddd! automatically when you log in")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
        .padding(16)
        .frame(width: 270)
    }
}

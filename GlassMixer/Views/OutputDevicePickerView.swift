import SwiftUI

/// Liquid Glass output-device picker: lists every selectable output device with its transport icon,
/// Bluetooth battery (when available), a default checkmark, tap-to-switch, and a per-device hardware
/// volume slider for devices that expose one.
struct OutputDevicePickerView: View {
    @Bindable var store: MixerStore
    var onSelect: () -> Void

    @Namespace private var glassNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "hifispeaker.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Output Device")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
            }

            if store.availableDevices.isEmpty {
                Text("No output devices found.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                LiquidGlassGroup(spacing: 8) {
                    ForEach(store.availableDevices) { device in
                        deviceRow(device)
                            .glassMorphID(device.id, in: glassNamespace)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func deviceRow(_ device: AudioDevice) -> some View {
        VStack(spacing: 8) {
            Button {
                store.selectDevice(device)
                onSelect()
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: device.transport.iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 26)
                        .foregroundStyle(device.isDefaultOutput ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(device.transport.label)
                            if let battery = device.batteryPercent {
                                Label("\(battery)%", systemImage: batteryIcon(battery))
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if device.isDefaultOutput {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if device.canControlVolume, let volume = device.volume {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    LiquidSlider(
                        value: Binding(
                            get: { volume },
                            set: { store.setDeviceVolume($0, for: device) }
                        ),
                        range: 0...1
                    ) { _ in }
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(11)
        .glassCard(cornerRadius: 15, interactive: true, tint: device.isDefaultOutput ? .accentColor : nil)
    }

    private func batteryIcon(_ percent: Int) -> String {
        switch percent {
        case ..<15: return "battery.0percent"
        case ..<40: return "battery.25percent"
        case ..<65: return "battery.50percent"
        case ..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

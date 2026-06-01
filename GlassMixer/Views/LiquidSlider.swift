import SwiftUI

/// Clean, neutral volume slider: a soft translucent track with a single tasteful accent fill and a
/// white knob. Greys out automatically when disabled (e.g. a muted app). The 100% point is marked
/// with a subtle tick so boosting above unity is legible.
struct LiquidSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var accent: [Color] = [.blue, .indigo]
    let onEditingChanged: (Double) -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isDragging = false

    private let knobSize: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let progress = normalizedProgress
            let fillWidth = max(knobSize, width * progress)
            let unityX = width * unityProgress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.14))

                if range.upperBound > 1 {
                    // Unity (100%) marker.
                    Capsule()
                        .fill(.white.opacity(0.35))
                        .frame(width: 2, height: 12)
                        .offset(x: min(max(unityX - 1, 0), width - 2))
                }

                Capsule()
                    .fill(fillStyle)
                    .frame(width: fillWidth)
                    .shadow(color: (accent.first ?? .blue).opacity(isEnabled ? (isDragging ? 0.45 : 0.28) : 0), radius: isDragging ? 8 : 5)

                Circle()
                    .fill(.white)
                    .frame(width: isDragging ? knobSize + 3 : knobSize, height: isDragging ? knobSize + 3 : knobSize)
                    .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 2)
                    .offset(x: min(max(fillWidth - knobSize, 0), width - knobSize))
            }
            .frame(height: knobSize)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        updateValue(locationX: gesture.location.x, width: width)
                        onEditingChanged(value)
                    }
                    .onEnded { gesture in
                        updateValue(locationX: gesture.location.x, width: width)
                        isDragging = false
                        onEditingChanged(value)
                    }
            )
            .animation(.smooth(duration: 0.16), value: value)
            .animation(.spring(response: 0.24, dampingFraction: 0.7), value: isDragging)
        }
        .frame(height: 18)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(value * 100)) percent")
    }

    private var fillStyle: AnyShapeStyle {
        if isEnabled {
            return AnyShapeStyle(
                LinearGradient(colors: accent, startPoint: .leading, endPoint: .trailing)
            )
        }
        return AnyShapeStyle(Color.secondary)
    }

    private var normalizedProgress: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private var unityProgress: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((1 - range.lowerBound) / span, 0), 1)
    }

    private func updateValue(locationX: CGFloat, width: CGFloat) {
        let progress = min(max(locationX / max(width, 1), 0), 1)
        let nextValue = range.lowerBound + Double(progress) * (range.upperBound - range.lowerBound)
        value = min(max(nextValue, range.lowerBound), range.upperBound)
    }
}

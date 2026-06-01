import SwiftUI

struct LiquidSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onEditingChanged: (Double) -> Void

    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let progress = normalizedProgress
            let width = proxy.size.width
            let fillWidth = max(8, width * progress)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.black.opacity(0.12))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.cyan, .blue, .purple.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth)
                    .shadow(color: .blue.opacity(isDragging ? 0.38 : 0.2), radius: isDragging ? 9 : 5)

                Circle()
                    .fill(.white)
                    .frame(width: isDragging ? 18 : 15, height: isDragging ? 18 : 15)
                    .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 2)
                    .offset(x: min(max(fillWidth - 9, 0), width - 18))
            }
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
            .animation(.smooth(duration: 0.18), value: value)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isDragging)
        }
        .frame(height: 18)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(value * 100)) percent")
    }

    private var normalizedProgress: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private func updateValue(locationX: CGFloat, width: CGFloat) {
        let progress = min(max(locationX / max(width, 1), 0), 1)
        let nextValue = range.lowerBound + Double(progress) * (range.upperBound - range.lowerBound)
        value = min(max(nextValue, range.lowerBound), range.upperBound)
    }
}

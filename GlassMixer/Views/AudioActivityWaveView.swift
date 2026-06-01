import SwiftUI

struct AudioActivityWaveView: View {
    let level: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let datePhase = timeline.date.timeIntervalSinceReferenceDate * 5
                let bars = 5
                let spacing = size.width / CGFloat(bars)

                for index in 0..<bars {
                    let wave = (sin(datePhase + Double(index) * 0.9) + 1) / 2
                    let height = max(3, size.height * CGFloat(0.18 + wave * level))
                    let x = CGFloat(index) * spacing + spacing * 0.28
                    let rect = CGRect(
                        x: x,
                        y: (size.height - height) / 2,
                        width: max(2, spacing * 0.42),
                        height: height
                    )

                    context.fill(
                        Path(roundedRect: rect, cornerRadius: rect.width / 2),
                        with: .color(.green.opacity(0.55 + min(level, 1) * 0.35))
                    )
                }
            }
        }
        .opacity(level > 0.04 ? 1 : 0.25)
    }
}

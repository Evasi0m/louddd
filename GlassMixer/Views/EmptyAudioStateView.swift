import SwiftUI

struct EmptyAudioStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "speaker.slash")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("No active audio")
                .font(.system(size: 13, weight: .semibold))

            Text("Apps will appear here when they start producing sound.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

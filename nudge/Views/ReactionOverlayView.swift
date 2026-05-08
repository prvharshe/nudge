import SwiftUI

struct ReactionOverlayView: View {
    let didMove: Bool
    let reactionText: String?   // nil = still loading
    let onDismiss: () -> Void

    @State private var dismissed = false
    @State private var textVisible = false

    private var emoji: String { didMove ? "🙌" : "😴" }

    var body: some View {
        ZStack {
            // Dark scrim
            Theme.ink.opacity(0.94)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            AmbientBackground()
                .opacity(0.42)
                .allowsHitTesting(false)

            VStack(spacing: 20) {
                Text(emoji)
                    .font(.system(size: 68))

                Text("Logged!")
                    .font(.title.bold())
                    .foregroundStyle(Theme.brandCream)

                if let text = reactionText {
                    Text(text)
                        .font(.body)
                        .foregroundStyle(Theme.brandCream.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .opacity(textVisible ? 1 : 0)
                        .offset(y: textVisible ? 0 : 8)
                        .onAppear {
                            withAnimation(.easeOut(duration: 0.4)) { textVisible = true }
                            // Auto-dismiss 2.5s after reaction appears
                            scheduleDismiss(after: 2.5)
                        }
                } else {
                    ProgressView()
                        .tint(Theme.brandCream.opacity(0.5))
                        .scaleEffect(0.8)
                }

                Text("Tap to continue")
                    .font(.caption)
                    .foregroundStyle(Theme.brandCream.opacity(0.36))
                    .padding(.top, 8)
            }
        }
        .onAppear {
            // Hard fallback — dismiss after 5s no matter what
            scheduleDismiss(after: 5)
        }
    }

    private func scheduleDismiss(after seconds: Double) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            await MainActor.run { dismiss() }
        }
    }

    private func dismiss() {
        guard !dismissed else { return }
        dismissed = true
        onDismiss()
    }
}

#Preview {
    ReactionOverlayView(
        didMove: true,
        reactionText: "That's your third walk this week — you're building a real rhythm.",
        onDismiss: {}
    )
}

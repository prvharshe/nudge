import SwiftUI

struct MorningNudgeView: View {
    @State private var message: String? = nil
    @State private var isLoading = true
    @State private var hasFailed = false

    private let cachedKey = "nudge.morningNudgeText"
    private let cachedDateKey = "nudge.morningNudgeDate"

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse, isActive: isLoading)

                if isLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Getting your nudge...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let message {
                    Text(message)
                        .font(.title3.weight(.medium))
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                        .padding(.horizontal, 4)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if hasFailed {
                    Text("Keep going — every day counts.")
                        .font(.title3.weight(.medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .animation(.easeInOut(duration: 0.4), value: message)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
        .task {
            await loadNudge()
        }
    }

    private func loadNudge() async {
        // Return cached message if it's from today
        if let cached = UserDefaults.standard.string(forKey: cachedKey),
           let cachedDate = UserDefaults.standard.object(forKey: cachedDateKey) as? Date,
           Calendar.current.isDateInToday(cachedDate) {
            message = cached
            isLoading = false
            return
        }

        do {
            let fetched = try await BackendService.fetchNudge()
            UserDefaults.standard.set(fetched, forKey: cachedKey)
            UserDefaults.standard.set(Date.now, forKey: cachedDateKey)
            message = fetched
        } catch {
            hasFailed = true
        }
        isLoading = false
    }
}

#Preview {
    MorningNudgeView()
}

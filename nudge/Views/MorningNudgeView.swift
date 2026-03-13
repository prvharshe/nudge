import SwiftUI

struct MorningNudgeView: View {
    @State private var message: String? = nil
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var hasFailed = false

    private let cachedKey     = "nudge.morningNudgeText"
    private let cachedDateKey = "nudge.morningNudgeDate"

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse, isActive: isLoading || isRefreshing)

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

            // Refresh button — lets user regenerate if the nudge feels off
            Button {
                Task { await refreshNudge() }
            } label: {
                HStack(spacing: 6) {
                    if isRefreshing {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    Text(isRefreshing ? "Refreshing…" : "Refresh nudge")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .disabled(isLoading || isRefreshing)
            .padding(.bottom, 32)
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
        await fetchFromServer(refresh: false)
    }

    private func refreshNudge() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        // Clear local cache so we don't immediately serve the old value
        UserDefaults.standard.removeObject(forKey: cachedKey)
        UserDefaults.standard.removeObject(forKey: cachedDateKey)
        await fetchFromServer(refresh: true)
        isRefreshing = false
    }

    private func fetchFromServer(refresh: Bool) async {
        do {
            let fetched = try await BackendService.fetchNudge(refresh: refresh)
            UserDefaults.standard.set(fetched, forKey: cachedKey)
            UserDefaults.standard.set(Date.now, forKey: cachedDateKey)
            withAnimation { message = fetched }
        } catch {
            hasFailed = true
        }
        isLoading = false
    }
}

#Preview {
    MorningNudgeView()
}

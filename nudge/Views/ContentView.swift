import SwiftUI
import SwiftData
import WidgetKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var entries: [Entry]

    @State private var selectedTab = 0
    @State private var showMorningNudge = false
    @State private var showSettings = false

    // Check-in flow state
    @State private var checkInStep: CheckInStep = .prompt

    var todayEntry: Entry? {
        entries.first { Calendar.current.isDateInToday($0.date) }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                todayTab
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            .tag(0)

            CalendarView()
                .tabItem { Label("History", systemImage: "calendar") }
                .tag(1)

            CoachView()
                .tabItem { Label("Coach", systemImage: "brain") }
                .tag(2)
        }
        .sheet(isPresented: $showMorningNudge) {
            MorningNudgeView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nudgeLaunchType)) { note in
            guard let type = note.object as? String else { return }
            selectedTab = 0
            if type == "checkin" {
                checkInStep = .prompt
            } else if type == "nudge" {
                showMorningNudge = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                processPendingWidgetCheckIn()
                // If today is already logged, cancel any pending follow-up reminder
                if todayEntry != nil {
                    NotificationService.cancelFollowUp()
                }
            }
        }
    }

    // MARK: - Widget pending check-in

    /// When the user taps YES/NO in the widget, the intent writes a pending
    /// record to the shared App Group. The next time the app comes to the
    /// foreground we pick it up, create a SwiftData entry, and sync it.
    private func processPendingWidgetCheckIn() {
        guard todayEntry == nil,                          // not already logged
              let pending = SharedStore.pendingCheckIn    // widget left something
        else { return }

        let entry = Entry(
            date: pending.date,
            didMove: pending.didMove
        )
        modelContext.insert(entry)
        SharedStore.clearPendingCheckIn()
        NotificationService.cancelFollowUp()
        // todayCheckIn already written by the intent — widget is already showing result
        WidgetCenter.shared.reloadAllTimelines()

        Task { try? await BackendService.syncEntry(entry) }
    }

    // MARK: - Today Tab

    @ViewBuilder
    private var todayTab: some View {
        if let entry = todayEntry {
            TodayDoneView(entry: entry, showMorningNudge: $showMorningNudge)
        } else {
            switch checkInStep {
            case .prompt:
                CheckInView { didMove in
                    withAnimation { checkInStep = .followUp(didMove: didMove) }
                }
            case .followUp(let didMove):
                FollowUpView(didMove: didMove) {
                    withAnimation { checkInStep = .prompt }
                }
            }
        }
    }
}

// MARK: - Check-in flow state

enum CheckInStep: Equatable {
    case prompt
    case followUp(didMove: Bool)
}

// MARK: - Today Done View (already logged)

struct TodayDoneView: View {
    let entry: Entry
    @Binding var showMorningNudge: Bool
    @Query private var allEntries: [Entry]

    private let activityLabels: [String: String] = [
        "walk": "🚶 Walk",
        "run": "🏃 Run",
        "tired": "😴 Too tired",
        "busy": "💼 Busy day"
    ]

    // Consecutive moved days ending today + all-time best
    private var streak: (current: Int, best: Int) {
        let cal = Calendar.current
        let movedDays = Set(allEntries.filter { $0.didMove }.map { cal.startOfDay(for: $0.date) })

        // Current streak: walk back from today
        var current = 0
        var date = cal.startOfDay(for: Date.now)
        while movedDays.contains(date) {
            current += 1
            date = cal.date(byAdding: .day, value: -1, to: date)!
        }

        // All-time best: scan sorted days for longest consecutive run
        let sorted = movedDays.sorted()
        var best = current
        var run = 1
        for i in 1..<sorted.count {
            let gap = cal.dateComponents([.day], from: sorted[i - 1], to: sorted[i]).day ?? 0
            run = gap == 1 ? run + 1 : 1
            best = max(best, run)
        }

        return (current, best)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Status badge
                VStack(spacing: 12) {
                    Text(entry.didMove ? "🙌" : "😴")
                        .font(.system(size: 56))

                    Text(entry.didMove ? "You moved today" : "Rest day logged")
                        .font(.title2.bold())

                    Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Streak badge — only shown when on a streak
                if streak.current > 0 {
                    HStack(spacing: 6) {
                        Text("🔥")
                        Text("\(streak.current) day streak")
                            .font(.subheadline.weight(.semibold))
                        if streak.best > streak.current {
                            Text("· best \(streak.best)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(Capsule())
                }

                // Activities
                if !entry.activities.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(entry.activities, id: \.self) { tag in
                            Text(activityLabels[tag] ?? tag)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(.systemGray6))
                                .clipShape(Capsule())
                        }
                    }
                    .flexibleRow()
                }

                // Note
                if let note = entry.note {
                    Text("\"\(note)\"")
                        .font(.subheadline.italic())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Morning nudge CTA
            Button {
                showMorningNudge = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                    Text("See your morning nudge")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor.opacity(0.12))
                .foregroundStyle(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Flexible row helper

extension View {
    func flexibleRow() -> some View {
        self.frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let nudgeLaunchType = Notification.Name("nudgeLaunchType")
}

#Preview {
    ContentView()
        .modelContainer(for: Entry.self, inMemory: true)
}

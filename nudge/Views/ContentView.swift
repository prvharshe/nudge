import SwiftUI
import SwiftData
import WidgetKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var entries: [Entry]

    @EnvironmentObject private var sceneManager: SceneManager
    @AppStorage("nudge.onboardingComplete") private var onboardingComplete = false

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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        // SceneKit handles day/night transition via SCNTransaction
                        TrackSceneView(isDark: sceneManager.isDark)
                            .ignoresSafeArea()
                    }
                    .navigationTitle("Today")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.85)) {
                                    sceneManager.toggle()
                                }
                            } label: {
                                Image(systemName: sceneManager.isDark ? "sun.max.fill" : "moon.stars.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(Theme.blue)
                                    .font(.system(size: 17, weight: .medium))
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                                    .foregroundStyle(.secondary)
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: Circle())
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
        .fullScreenCover(isPresented: .constant(!onboardingComplete)) {
            OnboardingView()
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
                // Reset daily repeating notifications (clears stale one-shots from prior days)
                NotificationService.scheduleAll()
                processPendingWidgetCheckIn()
                // If today is already logged, swap the evening check-in for an encouraging nudge
                if todayEntry != nil {
                    NotificationService.updateEveningForLoggedDay()
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

        Task {
            let stats = await HealthKitService.shared.fetchStats(for: entry.date)
            try? await BackendService.syncEntry(entry, stats: stats)
        }
    }

    // MARK: - Today Tab

    @ViewBuilder
    private var todayTab: some View {
        if let entry = todayEntry {
            TodayDoneView(entry: entry, showMorningNudge: $showMorningNudge)
        } else {
            switch checkInStep {
            case .prompt:
                CheckInView { didMove, preselectedTag in
                    withAnimation { checkInStep = .followUp(didMove: didMove, preselectedTag: preselectedTag) }
                }
            case .followUp(let didMove, let preselectedTag):
                FollowUpView(didMove: didMove, preselectedTag: preselectedTag) {
                    withAnimation { checkInStep = .prompt }
                }
            }
        }
    }
}

// MARK: - Check-in flow state

enum CheckInStep: Equatable {
    case prompt
    case followUp(didMove: Bool, preselectedTag: String?)
}

// MARK: - Today Done View (already logged)

struct TodayDoneView: View {
    let entry: Entry
    @Binding var showMorningNudge: Bool
    @Query private var allEntries: [Entry]
    @State private var todaySteps: Int? = nil

    private let activityLabels: [String: String] = [
        "walk": "🚶 Walk",
        "run": "🏃 Run",
        "tired": "😴 Too tired",
        "busy": "💼 Busy day"
    ]

    private var accent: Color { entry.didMove ? Theme.green : Theme.muted }

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

    @Environment(\.colorScheme) private var colorScheme

    private var accentColor: Color {
        entry.didMove
            ? (colorScheme == .dark ? Color(hex: "52D990") : Theme.green)
            : (colorScheme == .dark ? Color(hex: "C8AA8E") : Theme.muted)
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 22) {
                    // ── Hero status card (frosted glass, color-tinted) ──────────
                    VStack(spacing: 18) {
                        Text(entry.didMove ? "🙌" : "😴")
                            .font(.system(size: 66))

                        VStack(spacing: 6) {
                            Text(entry.didMove ? "You moved today" : "Rest day logged")
                                .font(.system(.title2, design: .rounded).weight(.bold))
                                .foregroundStyle(accentColor)

                            Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 42)
                    .background {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(accent.opacity(colorScheme == .dark ? 0.18 : 0.08))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(accent.opacity(colorScheme == .dark ? 0.35 : 0.20), lineWidth: 1)
                    )

                    // ── Streak ──────────────────────────────────────────────────
                    if streak.current > 0 {
                        HStack(spacing: 6) {
                            Text("🔥")
                            Text("\(streak.current) day streak")
                                .font(.subheadline.weight(.semibold))
                            if streak.best > streak.current {
                                Text("· best \(streak.best)")
                                    .font(.caption)
                                    .foregroundStyle(.orange.opacity(0.75))
                            }
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.orange.opacity(0.35), lineWidth: 1))
                    }

                    // ── Step count ───────────────────────────────────────────────
                    if let steps = todaySteps, steps > 0 {
                        Text("\(steps.formatted()) steps today")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                    }

                    // ── Activity chips (frosted) ─────────────────────────────────
                    if !entry.activities.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(entry.activities, id: \.self) { tag in
                                Text(activityLabels[tag] ?? tag)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }

                    // ── Note ─────────────────────────────────────────────────────
                    if let note = entry.note, !note.isEmpty {
                        Text("\"\(note)\"")
                            .font(.subheadline.italic())
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 120)
            }
        }
        // ── Floating CTA ─────────────────────────────────────────────────────────
        .task {
            let stats = await HealthKitService.shared.fetchStats(for: .now)
            todaySteps = stats?.steps
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                showMorningNudge = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.subheadline.weight(.semibold))
                    Text("See your morning nudge")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(Theme.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 10)
            .background(.ultraThinMaterial)
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

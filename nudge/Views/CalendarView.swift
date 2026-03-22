import SwiftUI
import SwiftData
import Charts

struct CalendarView: View {
    @Query private var entries: [Entry]
    @State private var displayMonth = Date.now
    @State private var selectedEntry: Entry? = nil

    // Weekly insight
    @State private var weeklyInsight: String? = nil
    @State private var weeklyInsightLoading = false
    @State private var insightExpanded = false

    // 7-day step chart
    @State private var weeklySteps: [(date: Date, steps: Int)] = []

    // Auto-fill missed days
    @State private var missedDays: [Date] = []
    @State private var retroDate: Date? = nil
    @State private var showRetroSheet = false

    private let insightTextKey = "nudge.weeklyInsightText"
    private let insightDateKey  = "nudge.weeklyInsightDate"

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdaySymbols = Calendar.current.veryShortWeekdaySymbols

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if !missedDays.isEmpty {
                        missedDaysBanner
                    }
                    weeklyInsightCard
                    if !weeklySteps.isEmpty {
                        weeklyStepsChart
                    }
                    monthHeader
                    weekdayRow
                    dayGrid
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(item: $selectedEntry) { entry in
            EntryDetailView(entry: entry)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showRetroSheet) {
            if let date = retroDate {
                retroLogSheet(for: date)
            }
        }
        .onAppear {
            loadOrGenerateInsight()
            loadWeeklySteps()
            loadMissedDays()
        }
    }

    // MARK: - Missed days banner

    private var missedDaysBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(missedDays, id: \.self) { day in
                HStack(spacing: 10) {
                    Image(systemName: "figure.walk.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.green)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Looks like you moved on \(day.formatted(.dateTime.weekday(.wide)))")
                            .font(.subheadline.weight(.semibold))
                        Text("Want to log it retroactively?")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Log it") {
                        retroDate = day
                        showRetroSheet = true
                    }
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.green)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    @ViewBuilder
    private func retroLogSheet(for date: Date) -> some View {
        FollowUpView(didMove: true, entryDate: date, onDone: {
            missedDays.removeAll { calendar.isDate($0, inSameDayAs: date) }
            showRetroSheet = false
            retroDate = nil
        })
        .presentationDetents([.large])
    }

    // MARK: - Weekly insight card

    private var weeklyInsightCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("This week", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    generateInsight()
                } label: {
                    Image(systemName: weeklyInsightLoading ? "ellipsis" : "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .disabled(weeklyInsightLoading)
            }

            if weeklyInsightLoading && weeklyInsight == nil {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Analysing your patterns…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if let insight = weeklyInsight {
                Text(insightExpanded ? insight : firstSentence(of: insight))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.easeInOut(duration: 0.2), value: insightExpanded)

                if insight != firstSentence(of: insight) {
                    Button(insightExpanded ? "Show less" : "Read more") {
                        withAnimation { insightExpanded.toggle() }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.blue)
                }
            } else {
                Text("Tap ↻ to generate your weekly pattern analysis.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 7-day step chart

    private var weeklyStepsChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Steps · last 7 days")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Chart(weeklySteps, id: \.date) { item in
                BarMark(
                    x: .value("Day", item.date, unit: .day),
                    y: .value("Steps", item.steps)
                )
                .foregroundStyle(item.steps >= 4000 ? Theme.green : Theme.muted)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date.formatted(.dateTime.weekday(.narrow)))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 80)
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Month navigation header

    private var monthHeader: some View {
        HStack {
            Button {
                displayMonth = calendar.date(byAdding: .month, value: -1, to: displayMonth) ?? displayMonth
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            Text(displayMonth, format: .dateTime.month(.wide).year())
                .font(.title3.bold())

            Spacer()

            Button {
                displayMonth = calendar.date(byAdding: .month, value: 1, to: displayMonth) ?? displayMonth
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isFutureMonth ? Color.secondary.opacity(0.3) : .primary)
            }
            .disabled(isFutureMonth)
        }
    }

    private var isFutureMonth: Bool {
        let thisMonth = calendar.dateComponents([.year, .month], from: Date.now)
        let shown = calendar.dateComponents([.year, .month], from: displayMonth)
        return shown.year! > thisMonth.year! ||
               (shown.year! == thisMonth.year! && shown.month! >= thisMonth.month!)
    }

    // MARK: - Weekday labels

    private var weekdayRow: some View {
        HStack(spacing: 4) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Day grid

    private var dayGrid: some View {
        let days = daysInMonth(for: displayMonth)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<days.count, id: \.self) { index in
                if let date = days[index] {
                    let entryForDay = entry(for: date)
                    Button {
                        if let e = entryForDay {
                            selectedEntry = e
                        }
                    } label: {
                        DayCell(date: date, entry: entryForDay)
                    }
                    .buttonStyle(.plain)
                    .disabled(entryForDay == nil)
                } else {
                    Color.clear
                        .frame(height: 44)
                }
            }
        }
    }

    // MARK: - Data loading

    private func loadOrGenerateInsight() {
        if let text = UserDefaults.standard.string(forKey: insightTextKey),
           let date = UserDefaults.standard.object(forKey: insightDateKey) as? Date,
           isSameWeek(date, as: Date.now) {
            weeklyInsight = text
            return
        }
        generateInsight()
    }

    private func generateInsight() {
        guard !weeklyInsightLoading else { return }
        weeklyInsightLoading = true
        Task {
            if let text = try? await BackendService.fetchWeeklyInsight() {
                await MainActor.run {
                    weeklyInsight = text
                    insightExpanded = false
                    UserDefaults.standard.set(text, forKey: insightTextKey)
                    UserDefaults.standard.set(Date.now, forKey: insightDateKey)
                    weeklyInsightLoading = false
                }
            } else {
                await MainActor.run { weeklyInsightLoading = false }
            }
        }
    }

    private func loadWeeklySteps() {
        Task {
            let data = await HealthKitService.shared.fetchWeeklySteps()
            await MainActor.run { weeklySteps = data }
        }
    }

    private func loadMissedDays() {
        let loggedDates = Set(entries.map { calendar.startOfDay(for: $0.date) })
        Task {
            let missed = await HealthKitService.shared.findUnloggedMovedDays(
                lookback: 7,
                loggedDates: loggedDates
            )
            await MainActor.run { missedDays = missed }
        }
    }

    private func isSameWeek(_ a: Date, as b: Date) -> Bool {
        calendar.isDate(a, equalTo: b, toGranularity: .weekOfYear)
    }

    private func firstSentence(of text: String) -> String {
        if let range = text.range(of: ".", options: .literal) {
            let end = text.index(after: range.lowerBound)
            return String(text[..<end])
        }
        return text
    }

    // MARK: - Helpers

    private func daysInMonth(for date: Date) -> [Date?] {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let firstDay = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: firstDay) else {
            return []
        }

        let weekday = calendar.component(.weekday, from: firstDay) - 1
        var days: [Date?] = Array(repeating: nil, count: weekday)

        for day in range {
            var comps = components
            comps.day = day
            days.append(calendar.date(from: comps))
        }

        return days
    }

    private func entry(for date: Date) -> Entry? {
        let start = calendar.startOfDay(for: date)
        return entries.first { calendar.startOfDay(for: $0.date) == start }
    }
}

// MARK: - Day Cell

struct DayCell: View {
    let date: Date
    let entry: Entry?

    private let calendar = Calendar.current

    var isToday: Bool { calendar.isDateInToday(date) }
    var isFuture: Bool { date > Date.now }

    var body: some View {
        VStack(spacing: 4) {
            Text("\(calendar.component(.day, from: date))")
                .font(.callout.weight(isToday ? .bold : .regular))
                .foregroundStyle(isFuture ? .tertiary : .primary)

            if let entry {
                Circle()
                    .fill(entry.didMove ? Theme.green : Theme.muted)
                    .frame(width: 7, height: 7)
            } else {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 7, height: 7)
            }
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isToday ? Theme.blue.opacity(0.12) : Color.clear)
        )
    }
}

// MARK: - Entry Detail Sheet

struct EntryDetailView: View {
    let entry: Entry
    @Environment(\.dismiss) private var dismiss
    @State private var stats: DayStats? = nil

    private let activityLabels: [String: String] = [
        "walk": "🚶 Walk",
        "run": "🏃 Run",
        "tired": "😴 Too tired",
        "busy": "💼 Busy day"
    ]

    private var emoji: String { entry.didMove ? "🙌" : "😴" }
    private var statusText: String { entry.didMove ? "Moved" : "Rest day" }
    private var accent: Color { entry.didMove ? Theme.green : Theme.muted }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.muted)
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 24)

            VStack(spacing: 20) {
                // Emoji + status
                VStack(spacing: 10) {
                    Text(emoji)
                        .font(.system(size: 52))

                    Text(statusText)
                        .font(.title2.bold())
                        .foregroundStyle(accent)

                    Text(entry.date, format: .dateTime.weekday(.wide).month(.wide).day().year())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Activity chips
                if !entry.activities.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(entry.activities, id: \.self) { tag in
                            Text(activityLabels[tag] ?? tag)
                                .font(.subheadline)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Theme.card)
                                .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                // Note
                if let note = entry.note, !note.isEmpty {
                    Text("\"\(note)\"")
                        .font(.subheadline.italic())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // HealthKit stats
                if let s = stats {
                    VStack(spacing: 10) {
                        Divider()
                            .padding(.horizontal, 24)

                        // Movement stats row
                        HStack(spacing: 10) {
                            StatPill(icon: "figure.walk", value: s.steps.formatted(), label: "steps")

                            if let mins = s.workoutMinutes {
                                StatPill(icon: "clock", value: "\(mins) min", label: s.workoutType ?? "workout")
                            }

                            if let cal = s.calories {
                                StatPill(icon: "flame", value: "\(cal)", label: "cal")
                            }
                        }
                        .frame(maxWidth: .infinity)

                        // Heart metrics row
                        if s.restingHR != nil || s.hrv != nil {
                            HStack(spacing: 10) {
                                if let hr = s.restingHR {
                                    StatPill(icon: "heart.fill", value: "\(hr) BPM", label: "resting HR")
                                }
                                if let hv = s.hrv {
                                    StatPill(icon: "waveform.path.ecg", value: "\(hv)ms", label: "HRV")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }

                        // Sleep pill (separate row — clearly "night before")
                        if let sleep = s.sleepHours {
                            HStack(spacing: 6) {
                                Image(systemName: "moon.zzz.fill")
                                    .font(.caption)
                                    .foregroundStyle(Theme.purple)
                                Text(String(format: "%.1f hrs sleep the night before", sleep))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Theme.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 24)
            .animation(.easeInOut(duration: 0.25), value: stats != nil)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            stats = await HealthKitService.shared.fetchStats(for: entry.date)
        }
    }
}

// MARK: - Stat Pill

struct StatPill: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    CalendarView()
        .modelContainer(for: Entry.self, inMemory: true)
}

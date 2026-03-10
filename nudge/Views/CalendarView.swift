import SwiftUI
import SwiftData

struct CalendarView: View {
    @Query private var entries: [Entry]
    @State private var displayMonth = Date.now
    @State private var selectedEntry: Entry? = nil

    // Weekly insight
    @State private var weeklyInsight: String? = nil
    @State private var weeklyInsightLoading = false
    @State private var insightExpanded = false

    private let insightTextKey = "nudge.weeklyInsightText"
    private let insightDateKey  = "nudge.weeklyInsightDate"

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdaySymbols = Calendar.current.veryShortWeekdaySymbols

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    weeklyInsightCard
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
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onAppear { loadOrGenerateInsight() }
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
                    .foregroundStyle(Color.accentColor)
                }
            } else {
                Text("Tap ↻ to generate your weekly pattern analysis.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
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

    // MARK: - Weekly insight logic

    private func loadOrGenerateInsight() {
        // Show cached text immediately if it's from this calendar week
        if let text = UserDefaults.standard.string(forKey: insightTextKey),
           let date = UserDefaults.standard.object(forKey: insightDateKey) as? Date,
           isSameWeek(date, as: Date.now) {
            weeklyInsight = text
            return
        }
        // Nothing fresh — generate
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

    private func isSameWeek(_ a: Date, as b: Date) -> Bool {
        calendar.isDate(a, equalTo: b, toGranularity: .weekOfYear)
    }

    private func firstSentence(of text: String) -> String {
        // Split on ". " or "." at end of string
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
                    .fill(entry.didMove ? Color.green : Color(.systemGray4))
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
                .fill(isToday ? Color.accentColor.opacity(0.12) : Color.clear)
        )
    }
}

// MARK: - Entry Detail Sheet

struct EntryDetailView: View {
    let entry: Entry
    @Environment(\.dismiss) private var dismiss

    private let activityLabels: [String: String] = [
        "walk": "🚶 Walk",
        "run": "🏃 Run",
        "tired": "😴 Too tired",
        "busy": "💼 Busy day"
    ]

    private var emoji: String { entry.didMove ? "🙌" : "😴" }
    private var statusText: String { entry.didMove ? "Moved" : "Rest day" }
    private var accent: Color { entry.didMove ? .green : Color(.secondaryLabel) }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle area
            Capsule()
                .fill(Color(.systemGray4))
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
                                .background(Color(.systemGray6))
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
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

#Preview {
    CalendarView()
        .modelContainer(for: Entry.self, inMemory: true)
}

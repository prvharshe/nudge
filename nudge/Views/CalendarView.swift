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
            .refreshable {
                loadWeeklySteps()
                loadMissedDays()
                loadOrGenerateInsight()
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

            let movedDates = Set(entries.filter { $0.didMove }
                .map { calendar.startOfDay(for: $0.date) })
            Chart(weeklySteps, id: \.date) { item in
                BarMark(
                    x: .value("Day", item.date, unit: .day),
                    y: .value("Steps", item.steps)
                )
                .foregroundStyle(
                    movedDates.contains(calendar.startOfDay(for: item.date)) ? Theme.green : Theme.muted
                )
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
    @State private var stats: DayStats? = nil
    @State private var showEditSheet = false

    private var activityLabels: [String: String] {
        var labels: [String: String] = [
            "walk": "🚶 Walk",
            "run":  "🏃 Run",
            "tired": "😴 Too tired",
            "busy": "💼 Busy day"
        ]
        for a in ActivityStore.shared.activities {
            labels[a.id] = "\(a.emoji) \(a.label)"
        }
        return labels
    }

    private var emoji: String { entry.didMove ? "🙌" : "😴" }
    private var statusText: String { entry.didMove ? "Moved" : "Rest day" }
    private var accent: Color { entry.didMove ? Theme.green : Theme.muted }

    var body: some View {
        NavigationStack {
            ScrollView {
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
                    .padding(.top, 8)

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

                    // HealthKit swipeable stat cards
                    if let s = stats {
                        VStack(spacing: 6) {
                            Divider()
                                .padding(.horizontal, 24)

                            TabView {
                                StatCardMovement(s: s)

                                if s.restingHR != nil || s.hrv != nil || s.sleepHours != nil {
                                    StatCardRecovery(s: s)
                                }

                                if s.foodCalories != nil || s.protein != nil {
                                    StatCardNutrition(s: s)
                                }
                            }
                            .tabViewStyle(.page(indexDisplayMode: .automatic))
                            .frame(height: 150)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .animation(.easeInOut(duration: 0.25), value: stats != nil)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showEditSheet = true }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.blue)
                }
            }
        }
        .task {
            stats = await HealthKitService.shared.fetchStats(for: entry.date)
        }
        .sheet(isPresented: $showEditSheet) {
            EditEntryView(entry: entry)
        }
    }
}

// MARK: - Edit Entry Sheet

struct EditEntryView: View {
    @Bindable var entry: Entry
    @Environment(\.dismiss) private var dismiss

    private let defaultChips: [(emoji: String, label: String, tag: String)] = [
        ("🚶", "Walk", "walk"),
        ("🏃", "Run", "run"),
        ("😴", "Too tired", "tired"),
        ("💼", "Busy day", "busy")
    ]

    @State private var selectedTags: Set<String> = []
    @State private var note = ""
    @State private var didMove = false
    @State private var isSaving = false
    @State private var showAddActivity = false
    @FocusState private var noteFocused: Bool

    init(entry: Entry) {
        self.entry = entry
        _selectedTags = State(initialValue: Set(entry.activities))
        _note = State(initialValue: entry.note ?? "")
        _didMove = State(initialValue: entry.didMove)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // Moved / Rest toggle
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Did you move?")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) { didMove = true }
                            } label: {
                                HStack(spacing: 6) {
                                    Text("🙌")
                                    Text("Moved")
                                        .font(.subheadline.weight(.medium))
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(didMove ? Theme.green.opacity(0.15) : Theme.card)
                                .foregroundStyle(didMove ? Theme.green : .secondary)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(didMove ? Theme.green.opacity(0.4) : Color.clear, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.15), value: didMove)

                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) { didMove = false }
                            } label: {
                                HStack(spacing: 6) {
                                    Text("😴")
                                    Text("Rest day")
                                        .font(.subheadline.weight(.medium))
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(!didMove ? Theme.muted.opacity(0.2) : Theme.card)
                                .foregroundStyle(!didMove ? Theme.muted : .secondary)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(!didMove ? Theme.muted.opacity(0.5) : Color.clear, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.15), value: didMove)
                        }
                    }

                    // Activity chips
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Activities")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        FlowLayout(spacing: 10) {
                            ForEach(defaultChips, id: \.tag) { chip in
                                ChipButton(
                                    emoji: chip.emoji,
                                    label: chip.label,
                                    isSelected: selectedTags.contains(chip.tag)
                                ) {
                                    Haptics.impact(.light)
                                    toggleTag(chip.tag)
                                }
                            }
                            ForEach(ActivityStore.shared.activities) { chip in
                                ChipButton(
                                    emoji: chip.emoji,
                                    label: chip.label,
                                    isSelected: selectedTags.contains(chip.id)
                                ) {
                                    Haptics.impact(.light)
                                    toggleTag(chip.id)
                                }
                            }
                            Button { showAddActivity = true } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus")
                                        .font(.caption.weight(.bold))
                                    Text("Add")
                                        .font(.subheadline.weight(.medium))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Theme.card)
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .sheet(isPresented: $showAddActivity) {
                            AddActivitySheet()
                        }
                    }

                    // Note field
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Note")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField("Add a note… (optional)", text: $note, axis: .vertical)
                            .focused($noteFocused)
                            .lineLimit(3, reservesSpace: true)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.blue)
                    .disabled(isSaving)
                }
            }
            .onTapGesture { noteFocused = false }
        }
    }

    private func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) { selectedTags.remove(tag) }
        else { selectedTags.insert(tag) }
    }

    private func saveChanges() {
        guard !isSaving else { return }
        isSaving = true
        noteFocused = false
        Haptics.success()

        entry.didMove = didMove
        entry.activities = Array(selectedTags)
        entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.synced = false

        Task {
            let stats = await HealthKitService.shared.fetchStats(for: entry.date)
            try? await BackendService.syncEntry(entry, stats: stats)
            await MainActor.run {
                entry.synced = true
                isSaving = false
                dismiss()
            }
        }
    }
}

// MARK: - Shared metric column (used inside swipeable stat cards)

private struct MetricColumn: View {
    let value: String
    let label: String
    var color: Color = .primary
    var onInfo: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            HStack(spacing: 3) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if onInfo != nil {
                    Image(systemName: "info.circle")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onInfo?() }
    }
}

// MARK: - Movement card

private struct StatCardMovement: View {
    let s: DayStats
    @State private var shownInfo: MetricInfoContext? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Movement", systemImage: "figure.walk.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                MetricColumn(
                    value: s.steps > 0 ? s.steps.formatted() : "—",
                    label: "steps",
                    color: Theme.green,
                    onInfo: s.steps > 0 ? {
                        shownInfo = MetricInfoContext(info: MetricInfo.steps(value: s.steps), rawValue: "\(s.steps)")
                    } : nil
                )
                if let mins = s.workoutMinutes {
                    Divider().frame(height: 36)
                    MetricColumn(
                        value: "\(mins) min",
                        label: s.workoutType ?? "workout",
                        color: Theme.blue
                    )
                }
                if let cal = s.calories {
                    Divider().frame(height: 36)
                    MetricColumn(
                        value: "\(cal)",
                        label: "active cal",
                        color: .orange,
                        onInfo: {
                            shownInfo = MetricInfoContext(info: MetricInfo.calories(value: cal), rawValue: "\(cal)")
                        }
                    )
                }
            }
        }
        .padding(16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 24)
        .sheet(item: $shownInfo) { ctx in
            MetricInfoSheet(info: ctx.info, currentValue: ctx.rawValue)
                .presentationDetents([.large])
        }
    }
}

// MARK: - Recovery card

private struct StatCardRecovery: View {
    let s: DayStats
    @State private var shownInfo: MetricInfoContext? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recovery", systemImage: "heart.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                if let hr = s.restingHR {
                    MetricColumn(
                        value: "\(hr)",
                        label: "resting HR",
                        color: .red,
                        onInfo: {
                            shownInfo = MetricInfoContext(info: MetricInfo.restingHR(value: hr), rawValue: "\(hr)")
                        }
                    )
                }
                if let hv = s.hrv {
                    if s.restingHR != nil { Divider().frame(height: 36) }
                    MetricColumn(
                        value: "\(hv)ms",
                        label: "HRV",
                        color: Theme.purple,
                        onInfo: {
                            shownInfo = MetricInfoContext(info: MetricInfo.hrv(value: hv), rawValue: "\(hv)")
                        }
                    )
                }
                if let sleep = s.sleepHours {
                    if s.restingHR != nil || s.hrv != nil { Divider().frame(height: 36) }
                    MetricColumn(
                        value: String(format: "%.1fh", sleep),
                        label: "sleep",
                        color: .indigo,
                        onInfo: {
                            shownInfo = MetricInfoContext(info: MetricInfo.sleep(value: sleep), rawValue: String(format: "%.1f", sleep))
                        }
                    )
                }
            }
        }
        .padding(16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 24)
        .sheet(item: $shownInfo) { ctx in
            MetricInfoSheet(info: ctx.info, currentValue: ctx.rawValue)
                .presentationDetents([.large])
        }
    }
}

// MARK: - Nutrition card

private struct StatCardNutrition: View {
    let s: DayStats
    @State private var shownInfo: MetricInfoContext? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Nutrition", systemImage: "fork.knife.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let kcal = s.foodCalories {
                    Button {
                        shownInfo = MetricInfoContext(info: MetricInfo.calories(value: kcal), rawValue: "\(kcal)")
                    } label: {
                        HStack(spacing: 3) {
                            Text("\(kcal) kcal")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.primary)
                            Image(systemName: "info.circle")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 0) {
                if let p = s.protein {
                    MetricColumn(
                        value: "\(p)g",
                        label: "protein",
                        color: Theme.blue,
                        onInfo: {
                            shownInfo = MetricInfoContext(info: MetricInfo.protein(value: p), rawValue: "\(p)")
                        }
                    )
                }
                if let c = s.carbs {
                    if s.protein != nil { Divider().frame(height: 36) }
                    MetricColumn(value: "\(c)g", label: "carbs", color: Theme.green)
                }
                if let f = s.fat {
                    if s.protein != nil || s.carbs != nil { Divider().frame(height: 36) }
                    MetricColumn(value: "\(f)g", label: "fat", color: Theme.purple)
                }
            }
        }
        .padding(16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 24)
        .sheet(item: $shownInfo) { ctx in
            MetricInfoSheet(info: ctx.info, currentValue: ctx.rawValue)
                .presentationDetents([.large])
        }
    }
}

#Preview {
    CalendarView()
        .modelContainer(for: Entry.self, inMemory: true)
}

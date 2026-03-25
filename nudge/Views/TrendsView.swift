import SwiftUI
import SwiftData
import Charts

// MARK: - Trends View

struct TrendsView: View {
    @Query private var allEntries: [Entry]

    // HK-loaded data
    @State private var stepHistory:  [(date: Date, steps: Int)]    = []
    @State private var rhrHistory:   [(date: Date, rhr: Int)]      = []
    @State private var sleepHistory: [(date: Date, hours: Double)] = []
    @State private var nutrition = NutritionAvg()
    @State private var isLoading = true

    private let minimumEntries = 5
    private var isUnlocked: Bool { allEntries.count >= minimumEntries }

    var body: some View {
        NavigationStack {
            if isUnlocked {
                ScrollView {
                    VStack(spacing: 18) {
                        if isLoading {
                            ProgressView("Loading health data…")
                                .padding(.top, 60)
                        } else {
                            overviewCard
                            calendarCard
                            if !weekdayData.isEmpty { dayPatternCard }
                            if !stepHistory.isEmpty { stepTrendCard }
                            if sleepOnMovedDays != nil || sleepOnRestDays != nil { sleepCard }
                            if !rhrHistory.isEmpty { recoveryCard }
                            if nutrition.hasData { nutritionCard }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .navigationTitle("Trends")
                .navigationBarTitleDisplayMode(.large)
                .task { await loadData() }
            } else {
                lockedState
                    .navigationTitle("Trends")
                    .navigationBarTitleDisplayMode(.large)
            }
        }
    }

    // MARK: - Locked state

    private var lockedState: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    Text("📈")
                        .font(.system(size: 52))

                    VStack(spacing: 8) {
                        Text("Patterns need time")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .multilineTextAlignment(.center)

                        Text("Log \(minimumEntries) days of check-ins and Trends will start showing your movement patterns, step history, sleep correlation, and more.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 16)
                    }
                }

                // Progress dots
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        ForEach(0..<minimumEntries, id: \.self) { i in
                            ZStack {
                                Circle()
                                    .fill(i < allEntries.count ? Theme.green : Theme.card)
                                    .frame(width: 18, height: 18)
                                    .overlay(
                                        Circle().stroke(
                                            i < allEntries.count
                                                ? Theme.green.opacity(0.4)
                                                : Theme.blue.opacity(0.2),
                                            lineWidth: 1
                                        )
                                    )

                                if i < allEntries.count {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                    }

                    Text(allEntries.isEmpty
                         ? "No check-ins yet — start tonight"
                         : "\(allEntries.count) of \(minimumEntries) days logged")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(allEntries.isEmpty ? .secondary : .primary)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data loading

    private func loadData() async {
        async let steps   = HealthKitService.shared.fetchStepHistory(days: 30)
        async let rhr     = HealthKitService.shared.fetchRHRHistory(days: 14)
        async let sleep   = HealthKitService.shared.fetchSleepHistory(days: 30)
        async let nutr    = HealthKitService.shared.fetchNutritionAverages(days: 7)

        let (s, r, sl, n) = await (steps, rhr, sleep, nutr)
        await MainActor.run {
            stepHistory  = s
            rhrHistory   = r
            sleepHistory = sl
            nutrition    = NutritionAvg(kcal: n.kcal, protein: n.protein, carbs: n.carbs, fat: n.fat)
            isLoading    = false
        }
    }

    // MARK: - Derived from SwiftData entries

    private var cal: Calendar { .current }

    private var entryByDate: [Date: Entry] {
        Dictionary(uniqueKeysWithValues: allEntries.map {
            (cal.startOfDay(for: $0.date), $0)
        })
    }

    private var last30Dates: [Date] {
        (0..<30).reversed().compactMap {
            cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: .now))
        }
    }

    private var calendarDays: [CalendarDay] {
        last30Dates.map { date in
            if let e = entryByDate[date] {
                CalendarDay(date: date, state: e.didMove ? .moved : .rest)
            } else {
                CalendarDay(date: date, state: .noData)
            }
        }
    }

    private var movedCount:  Int { calendarDays.filter { $0.state == .moved }.count }
    private var loggedCount: Int { calendarDays.filter { $0.state != .noData }.count }

    private var currentStreak: Int {
        let moved = Set(allEntries.filter { $0.didMove }.map { cal.startOfDay(for: $0.date) })
        var streak = 0
        var date = cal.startOfDay(for: .now)
        while moved.contains(date) {
            streak += 1
            date = cal.date(byAdding: .day, value: -1, to: date)!
        }
        return streak
    }

    private var avgSteps30: Int {
        let pos = stepHistory.map(\.steps).filter { $0 > 0 }
        return pos.isEmpty ? 0 : pos.reduce(0, +) / pos.count
    }

    // Weekday pattern (1=Sun…7=Sat)
    private var weekdayData: [WeekdayDataPoint] {
        var counts: [Int: (moved: Int, total: Int)] = [:]
        for e in allEntries {
            let wd = cal.component(.weekday, from: e.date)
            var c = counts[wd] ?? (0, 0)
            c.total += 1
            if e.didMove { c.moved += 1 }
            counts[wd] = c
        }
        let labels = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        // Mon–Sun order (2…7, 1)
        return ([2, 3, 4, 5, 6, 7, 1]).compactMap { wd in
            guard let data = counts[wd], data.total >= 2 else { return nil }
            return WeekdayDataPoint(id: wd,
                                    label: labels[wd],
                                    rate: Double(data.moved) / Double(data.total))
        }
    }

    // Sleep correlation
    private var sleepOnMovedDays: Double? {
        average(of: sleepHoursFor(moved: true))
    }
    private var sleepOnRestDays: Double? {
        average(of: sleepHoursFor(moved: false))
    }
    private func sleepHoursFor(moved: Bool) -> [Double] {
        let dates = Set(allEntries.filter { $0.didMove == moved }.map { cal.startOfDay(for: $0.date) })
        return sleepHistory.filter { dates.contains(cal.startOfDay(for: $0.date)) }.map(\.hours)
    }
    private func average(of values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Overview card

    private var overviewCard: some View {
        TrendCard(title: "Last 30 Days") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(movedCount)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.green)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("days moved")
                            .font(.subheadline.weight(.medium))
                        Text("of \(loggedCount) logged")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Percentage ring
                    let pct = loggedCount > 0 ? Double(movedCount) / Double(loggedCount) : 0
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 7)
                        Circle()
                            .trim(from: 0, to: pct)
                            .stroke(Theme.green, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(pct * 100))%")
                            .font(.caption2.weight(.bold))
                    }
                    .frame(width: 52, height: 52)
                }

                HStack(spacing: 20) {
                    if currentStreak > 0 {
                        Label("\(currentStreak) day streak", systemImage: "flame.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                    if avgSteps30 > 0 {
                        Label("\(avgSteps30.formatted()) avg steps", systemImage: "figure.walk")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 30-day calendar dot grid

    private var calendarCard: some View {
        TrendCard(title: "Activity Calendar") {
            VStack(spacing: 10) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 6),
                    spacing: 5
                ) {
                    ForEach(calendarDays) { day in
                        Circle()
                            .fill(day.color)
                            .overlay(
                                Circle().stroke(Color.secondary.opacity(0.2), lineWidth: day.state == .noData ? 0.5 : 0)
                            )
                            .frame(height: 14)
                    }
                }

                HStack(spacing: 16) {
                    LegendDot(color: Theme.green, label: "Moved")
                    LegendDot(color: Color.secondary.opacity(0.25), label: "Rest")
                    LegendDot(color: Color.clear, label: "No log", stroke: true)
                    Spacer()
                    Text("oldest → newest")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Day-of-week pattern

    private var dayPatternCard: some View {
        TrendCard(title: "When You Move", subtitle: "Based on all logged entries") {
            Chart(weekdayData) { item in
                BarMark(
                    x: .value("Rate", item.rate),
                    y: .value("Day", item.label)
                )
                .foregroundStyle(
                    item.rate >= 0.7 ? Theme.green :
                    item.rate >= 0.4 ? Theme.blue  : Theme.muted
                )
                .cornerRadius(4)
            }
            .chartXScale(domain: 0...1)
            .chartXAxis {
                AxisMarks(values: [0, 0.5, 1.0]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v * 100))%").font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis { AxisMarks { _ in AxisValueLabel(horizontalSpacing: 6) } }
            .frame(height: 190)
        }
    }

    // MARK: - 30-day step trend

    private var stepTrendCard: some View {
        TrendCard(title: "Daily Steps", subtitle: "30 days · dashed line = average") {
            Chart {
                ForEach(stepHistory, id: \.date) { item in
                    BarMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Steps", item.steps)
                    )
                    .foregroundStyle(item.steps >= avgSteps30 ? Theme.green : Theme.muted.opacity(0.5))
                    .cornerRadius(2)
                }
                if avgSteps30 > 0 {
                    RuleMark(y: .value("Avg", avgSteps30))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 10)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text(v >= 1000 ? "\(v / 1000)k" : "\(v)").font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 160)
        }
    }

    // MARK: - Sleep & movement correlation

    private var sleepCard: some View {
        let maxH = max(sleepOnMovedDays ?? 0, sleepOnRestDays ?? 0) + 1.5
        return TrendCard(title: "Sleep & Movement", subtitle: "Average hours of sleep the night before") {
            VStack(spacing: 12) {
                if let h = sleepOnMovedDays {
                    SleepCompareRow(label: "Moved days", hours: h, color: Theme.green, maxHours: maxH)
                }
                if let h = sleepOnRestDays {
                    SleepCompareRow(label: "Rest days", hours: h, color: Theme.muted.opacity(0.7), maxHours: maxH)
                }

                if let moved = sleepOnMovedDays, let rest = sleepOnRestDays, moved > rest + 0.3 {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                        Text(String(format: "You tend to move more after %.1f+ hours of sleep", moved - 0.5))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - Recovery (RHR sparkline)

    private var recoveryCard: some View {
        let avgRHR = rhrHistory.isEmpty ? 0 : rhrHistory.map(\.rhr).reduce(0, +) / rhrHistory.count
        return TrendCard(title: "Resting Heart Rate", subtitle: "14 days · avg \(avgRHR) BPM") {
            Chart(rhrHistory, id: \.date) { item in
                LineMark(
                    x: .value("Date", item.date),
                    y: .value("BPM", item.rhr)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Theme.blue)
                PointMark(
                    x: .value("Date", item.date),
                    y: .value("BPM", item.rhr)
                )
                .symbolSize(25)
                .foregroundStyle(item.rhr > 80 ? Color.red : Theme.blue)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)").font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 130)
        }
    }

    // MARK: - Nutrition averages

    private var nutritionCard: some View {
        TrendCard(title: "Nutrition", subtitle: "7-day average · from Apple Health") {
            VStack(alignment: .leading, spacing: 14) {
                if let kcal = nutrition.kcal {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(kcal)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        Text("kcal / day")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let tdee = UserProfile.tdee.map({ Int($0) }) {
                            Text("target ~\(tdee) kcal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(spacing: 10) {
                    if let p = nutrition.protein {
                        MacroBar(label: "Protein", value: p, target: UserProfile.proteinTargetG, color: Theme.blue)
                    }
                    if let c = nutrition.carbs {
                        MacroBar(label: "Carbs", value: c, target: nil, color: Theme.green)
                    }
                    if let f = nutrition.fat {
                        MacroBar(label: "Fat", value: f, target: nil, color: Theme.purple)
                    }
                }
            }
        }
    }
}

// MARK: - Supporting types

private struct CalendarDay: Identifiable {
    let date: Date
    var id: Date { date }
    enum State { case moved, rest, noData }
    let state: State
    var color: Color {
        switch state {
        case .moved:  return Theme.green
        case .rest:   return Color.secondary.opacity(0.2)
        case .noData: return Color.clear
        }
    }
}

private struct WeekdayDataPoint: Identifiable {
    let id: Int
    let label: String
    let rate: Double
}

struct NutritionAvg {
    var kcal: Int?    = nil
    var protein: Int? = nil
    var carbs: Int?   = nil
    var fat: Int?     = nil
    var hasData: Bool { kcal != nil || protein != nil }
}

// MARK: - Sub-views

private struct TrendCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.bold))
                if let s = subtitle {
                    Text(s).font(.caption).foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String
    var stroke: Bool = false
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(stroke ? Color.clear : color)
                .overlay(stroke ? Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 0.5) : nil)
                .frame(width: 10, height: 10)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct SleepCompareRow: View {
    let label: String
    let hours: Double
    let color: Color
    let maxHours: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 75, alignment: .leading)
            Text(String(format: "%.1fh", hours))
                .font(.caption.weight(.bold))
                .frame(width: 38, alignment: .trailing)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(hours / max(maxHours, 1)), height: 14)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(height: 22)
    }
}

private struct MacroBar: View {
    let label: String
    let value: Int
    let target: Int?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Group {
                    Text("\(value)g").font(.caption.weight(.semibold))
                    if let t = target {
                        Text("/ \(t)g").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.1)).frame(height: 7)
                    let fill: CGFloat = target != nil
                        ? min(CGFloat(value) / CGFloat(target!), 1.0)
                        : 1.0
                    RoundedRectangle(cornerRadius: 4).fill(color.gradient).frame(width: geo.size.width * fill, height: 7)
                }
            }
            .frame(height: 7)
        }
    }
}

#Preview {
    TrendsView()
        .modelContainer(for: Entry.self, inMemory: true)
}

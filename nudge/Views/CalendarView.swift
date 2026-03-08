import SwiftUI
import SwiftData

struct CalendarView: View {
    @Query private var entries: [Entry]
    @State private var displayMonth = Date.now

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdaySymbols = Calendar.current.veryShortWeekdaySymbols

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
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
                    DayCell(date: date, entry: entry(for: date))
                } else {
                    Color.clear
                        .frame(height: 44)
                }
            }
        }
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

#Preview {
    CalendarView()
        .modelContainer(for: Entry.self, inMemory: true)
}

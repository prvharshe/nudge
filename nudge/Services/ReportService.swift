import Foundation

/// Weekly + monthly habit report card, emailed via the backend (POST /api/report-email).
/// Routine ticks and steps only live on this phone, so the raw days are gathered here;
/// the backend does the stats, grades and email rendering.
enum ReportService {
    struct RoutineDay: Encodable { let name: String; let detail: String; let done: Bool }
    struct Day: Encodable {
        let date: String
        let steps: Int?
        let routines: [RoutineDay]?   // nil = before routine tracking began
    }
    struct Report: Encodable {
        let kind: String              // "week" | "month"
        let start: String
        let end: String
        let stepGoal: Int
        let days: [Day]
    }

    private static var inFlight = false

    /// Sends the most recently completed week and month, once each. Safe to call on every foreground:
    /// a period is marked sent only after the backend accepts it, so failures retry next time.
    static func sendDueReports(now: Date = .now) async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        let cal = Calendar.current
        let periods: [(kind: String, unit: Calendar.Component)] = [("week", .weekOfYear), ("month", .month)]
        for (kind, unit) in periods {
            guard let current = cal.dateInterval(of: unit, for: now),
                  let previous = cal.dateInterval(of: unit, for: current.start.addingTimeInterval(-1)) else { continue }
            let sentKey = "nudge.report.\(kind).lastSentStart"
            let start = BackendService.calendarDateString(from: previous.start)
            guard UserDefaults.standard.string(forKey: sentKey) != start else { continue }

            let report = await build(kind: kind, interval: previous, now: now, calendar: cal)
            do {
                try await BackendService.sendReportEmail(report)
                UserDefaults.standard.set(start, forKey: sentKey)
            } catch {
                print("[ReportService] \(kind) report not sent: \(error)")
            }
        }
    }

    private static func build(kind: String, interval: DateInterval, now: Date, calendar cal: Calendar) async -> Report {
        // Step history is anchored on today, so fetch back far enough to cover the period.
        let span = (cal.dateComponents([.day], from: interval.start, to: cal.startOfDay(for: now)).day ?? 0) + 1
        let history = await HealthKitService.shared.fetchStepHistory(days: span)
        let stepsByDay = Dictionary(history.map { (RoutineStore.dayKey($0.date), $0.steps) },
                                    uniquingKeysWith: { a, _ in a })
        // All-zero means no Health access/data rather than a sedentary week; send "no data".
        let hasSteps = history.contains { interval.contains($0.date) && $0.steps > 0 }

        let firstTracked = RoutineStore.firstTrackedDayKey
        var days: [Day] = []
        var date = interval.start
        while date < interval.end {
            let key = RoutineStore.dayKey(date)
            // shortcut: uses today's routine list for past days, so edits rewrite history; store per-day schedules if that matters.
            let routines: [RoutineDay]? = firstTracked.map { key >= $0 } == true
                ? RoutineStore.scheduled(on: date).map {
                    RoutineDay(name: $0.name, detail: $0.detail, done: RoutineStore.isDone($0.id, on: date))
                }
                : nil
            days.append(Day(date: key, steps: hasSteps ? (stepsByDay[key] ?? 0) : nil, routines: routines))
            date = cal.date(byAdding: .day, value: 1, to: date)!
        }

        let lastDay = cal.date(byAdding: .day, value: -1, to: interval.end)!
        return Report(kind: kind,
                      start: RoutineStore.dayKey(interval.start),
                      end: RoutineStore.dayKey(lastDay),
                      stepGoal: Int(HealthKitService.shared.stepThreshold),
                      days: days)
    }
}

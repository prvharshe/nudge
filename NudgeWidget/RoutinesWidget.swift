//
//  RoutinesWidget.swift
//  NudgeWidget
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Intent

struct CompleteRoutineIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark routine done"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Routine ID") var routineID: String

    init() {}
    init(routineID: UUID) { self.routineID = routineID.uuidString }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: routineID) {
            RoutineStore.setDone(id, true, on: .now)   // reloads widgets
            await RoutineStore.rescheduleNotifications() // awaited: drop this slot's pending follow-up now
        }
        return .result()
    }
}

// MARK: - Timeline

struct RoutinesEntry: TimelineEntry {
    let date: Date
    let pending: [Routine]
    let totalToday: Int
}

struct RoutinesProvider: TimelineProvider {
    func placeholder(in context: Context) -> RoutinesEntry {
        RoutinesEntry(date: .now, pending: Array(RoutineStore.defaultRoutines.prefix(3)), totalToday: 4)
    }

    func getSnapshot(in context: Context, completion: @escaping (RoutinesEntry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RoutinesEntry>) -> Void) {
        let now = Date.now
        // Re-render when each routine becomes due (so it turns "overdue"), and at midnight for the new day.
        let dueTimes = RoutineStore.scheduled(on: now).map { $0.time(on: now) }.filter { $0 > now }
        let entries = [entry(at: now)] + Set(dueTimes).sorted().map { entry(at: $0) }
        let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: now)!)
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }

    private func entry(at date: Date) -> RoutinesEntry {
        RoutinesEntry(date: date,
                      pending: RoutineStore.pending(on: date),
                      totalToday: RoutineStore.scheduled(on: date).count)
    }
}

// MARK: - Views

struct RoutinesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RoutinesEntry

    private var maxRows: Int {
        switch family {
        case .systemSmall: 2
        case .systemLarge: 7
        default: 3
        }
    }

    var body: some View {
        Group {
            if family == .accessoryRectangular {
                accessory
            } else {
                list
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .widgetURL(URL(string: "nudge://routines"))
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Routines")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.totalToday - entry.pending.count)/\(entry.totalToday) done")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if entry.pending.isEmpty {
                Spacer()
                Label(entry.totalToday == 0 ? "Nothing today" : "All done today",
                      systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                Spacer()
            } else {
                ForEach(entry.pending.prefix(maxRows)) { routine in
                    row(routine)
                }
                if entry.pending.count > maxRows {
                    Text("+\(entry.pending.count - maxRows) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ routine: Routine) -> some View {
        let overdue = routine.time(on: entry.date) <= entry.date
        return HStack(spacing: 8) {
            Button(intent: CompleteRoutineIntent(routineID: routine.id)) {
                Image(systemName: "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(overdue ? Color.orange : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(routine.name) done")

            VStack(alignment: .leading, spacing: 0) {
                Text(routine.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if family != .systemSmall, !routine.detail.isEmpty {
                    Text(routine.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(routine.time(on: entry.date), format: .dateTime.hour().minute())
                .font(.caption2.weight(overdue ? .semibold : .regular))
                .foregroundStyle(overdue ? Color.orange : Color.secondary)
        }
    }

    @ViewBuilder
    private var accessory: some View {
        if let next = entry.pending.first {
            Button(intent: CompleteRoutineIntent(routineID: next.id)) {
                HStack {
                    Image(systemName: "circle")
                    VStack(alignment: .leading) {
                        Text(next.name).font(.headline).lineLimit(1)
                        Text(next.time(on: entry.date), format: .dateTime.hour().minute())
                            .font(.caption)
                        if entry.pending.count > 1 {
                            Text("+\(entry.pending.count - 1) more").font(.caption2)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
        } else {
            Label("Routines done", systemImage: "checkmark.circle.fill")
        }
    }
}

// MARK: - Widget Definition

struct RoutinesWidget: Widget {
    let kind = "RoutinesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RoutinesProvider()) { entry in
            RoutinesWidgetView(entry: entry)
        }
        .configurationDisplayName("Routines")
        .description("Today's medicines and routines. Tap to tick them off.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemMedium) {
    RoutinesWidget()
} timeline: {
    RoutinesEntry(date: .now, pending: Array(RoutineStore.defaultRoutines.prefix(3)), totalToday: 4)
    RoutinesEntry(date: .now, pending: [], totalToday: 4)
}

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline Entry

struct NudgeEntry: TimelineEntry {
    let date: Date
    let checkIn: CheckInRecord?
}

// MARK: - Timeline Provider

struct NudgeWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> NudgeEntry {
        NudgeEntry(date: .now, checkIn: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NudgeEntry) -> Void) {
        completion(NudgeEntry(date: .now, checkIn: SharedStore.todayCheckIn))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NudgeEntry>) -> Void) {
        let entry = NudgeEntry(date: .now, checkIn: SharedStore.todayCheckIn)
        // Refresh at midnight so the widget resets for a new day
        let midnight = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        )
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

// MARK: - Root View (routes to prompt or result)

struct NudgeWidgetView: View {
    let entry: NudgeEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let checkIn = entry.checkIn {
                CheckedInWidgetView(checkIn: checkIn)
            } else {
                CheckInPromptWidgetView()
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }
}

// MARK: - Prompt View (not yet logged today)

struct CheckInPromptWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // App label
            Text("nudge")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 6)

            // Prompt
            Text("Did you\nmove today?")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 10)

            // YES / NO buttons
            HStack(spacing: 8) {
                Button(intent: CheckInYesIntent()) {
                    HStack(spacing: 4) {
                        Text("🙌")
                            .font(.system(size: 14))
                        Text("Yes")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button(intent: CheckInNoIntent()) {
                    HStack(spacing: 4) {
                        Text("😴")
                            .font(.system(size: 14))
                        Text("No")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray5))
                    .foregroundStyle(Color(.secondaryLabel))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Checked-in View (already logged today)

struct CheckedInWidgetView: View {
    let checkIn: CheckInRecord

    private var emoji: String  { checkIn.didMove ? "🙌" : "😴" }
    private var label: String  { checkIn.didMove ? "Moved\ntoday"   : "Rest day\nlogged" }
    private var accent: Color  { checkIn.didMove ? .green           : Color(.secondaryLabel) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Top row: app name + date
            HStack(alignment: .firstTextBaseline) {
                Text("nudge")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Date.now, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Big emoji
            Text(emoji)
                .font(.system(size: 38))

            Spacer(minLength: 4)

            // Status label
            Text(label)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .lineSpacing(2)
                .foregroundStyle(accent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        // Tapping the whole widget opens the app
        .widgetURL(URL(string: "nudge://open"))
    }
}

// MARK: - Widget Definition

struct NudgeWidget: Widget {
    let kind = "NudgeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NudgeWidgetProvider()) { entry in
            NudgeWidgetView(entry: entry)
        }
        .configurationDisplayName("Nudge")
        .description("Log your daily movement in one tap.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    NudgeWidget()
} timeline: {
    NudgeEntry(date: .now, checkIn: nil)
    NudgeEntry(date: .now, checkIn: CheckInRecord(didMove: true,  date: .now))
    NudgeEntry(date: .now, checkIn: CheckInRecord(didMove: false, date: .now))
}

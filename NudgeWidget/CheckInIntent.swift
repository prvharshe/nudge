import AppIntents
import WidgetKit

// MARK: - Yes Intent

struct CheckInYesIntent: AppIntent {
    static var title: LocalizedStringResource = "I moved today"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        SharedStore.todayCheckIn   = CheckInRecord(didMove: true,  date: .now)
        SharedStore.pendingCheckIn = CheckInRecord(didMove: true,  date: .now)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - No Intent

struct CheckInNoIntent: AppIntent {
    static var title: LocalizedStringResource = "I didn't move today"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        SharedStore.todayCheckIn   = CheckInRecord(didMove: false, date: .now)
        SharedStore.pendingCheckIn = CheckInRecord(didMove: false, date: .now)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

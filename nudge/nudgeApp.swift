//
//  nudgeApp.swift
//  nudge
//
//  Created by Pranav Harshe on 07/03/26.
//

import SwiftUI
import SwiftData
import UserNotifications
import WidgetKit

@main
struct nudgeApp: App {
    let notificationDelegate = NotificationDelegate()
    @StateObject private var sceneManager = SceneManager()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Entry.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        notificationDelegate.container = sharedModelContainer
        UNUserNotificationCenter.current().delegate = notificationDelegate
        NotificationService.registerCategories()
        // Schedule notifications on every launch — no-ops gracefully if permission not yet granted.
        // Permission is requested during onboarding (OnboardingView step 3).
        NotificationService.scheduleAll()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sceneManager)
                .preferredColorScheme(sceneManager.preferredScheme)
                .onOpenURL { url in
                    // Widget tap-through: nudge://open brings the app to front; nudge://routines opens that tab.
                    if url.host == "routines" {
                        NotificationCenter.default.post(name: .nudgeLaunchType, object: "routines")
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        .backgroundTask(.appRefresh("processPendingCheckIn")) {
            // Handled in ContentView via scenePhase instead
        }
    }
}

// MARK: - Notification Delegate

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var container: ModelContainer?

    // Show notification banners even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // Handle notification buttons, and route to the correct screen on a plain tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        switch response.actionIdentifier {
        case NotificationActions.routineDone:
            await NotificationService.completeRoutines(userInfo: content.userInfo)
            await MainActor.run {
                NotificationCenter.default.post(name: .nudgeRoutinesChanged, object: nil)
            }
        case NotificationActions.routineSnooze:
            await NotificationService.snoozeRoutines(content: content)
        case NotificationActions.checkInYes, NotificationActions.checkInNo:
            let day = (content.userInfo["day"] as? String).flatMap { RoutineStore.date(forDayKey: $0) }
            await logCheckIn(didMove: response.actionIdentifier == NotificationActions.checkInYes, day: day ?? .now)
            // Awaited so iOS doesn't suspend a cold-launched app before its own reschedule has settled.
            await NotificationService.rescheduleCheckIns()
        case UNNotificationDefaultActionIdentifier:
            let type = content.userInfo["type"] as? String ?? ""
            await MainActor.run {
                NotificationCenter.default.post(name: .nudgeLaunchType, object: type)
            }
        default:
            break
        }
    }

    /// Saves the answer for the day the notification was about (a late tap can land after midnight).
    /// Upload is left to ContentView's next sync: Health data can't be read while the phone is locked,
    /// and syncing now would store the entry without it.
    @MainActor
    private func logCheckIn(didMove: Bool, day: Date) {
        guard let context = container?.mainContext else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.date >= start && $0.date < end })
        // An answer already given for this day wins; a stale notification must not overwrite it.
        guard (try? context.fetchCount(descriptor)) == 0 else { return }
        // A widget answer has no Entry until the next foreground, but it was still given first.
        if cal.isDateInToday(start), SharedStore.todayCheckIn != nil { return }

        context.insert(Entry(date: start, didMove: didMove))
        do {
            try context.save()
        } catch {
            print("[NotificationDelegate] Could not save check-in: \(error)")
            return
        }
        guard cal.isDateInToday(start) else { return }
        SharedStore.todayCheckIn = CheckInRecord(didMove: didMove, date: start)
        SharedStore.clearPendingCheckIn()
        CheckInReminders.cancel(on: start)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

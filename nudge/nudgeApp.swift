//
//  nudgeApp.swift
//  nudge
//
//  Created by Pranav Harshe on 07/03/26.
//

import SwiftUI
import SwiftData
import UserNotifications

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
        UNUserNotificationCenter.current().delegate = notificationDelegate
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
    // Show notification banners even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // Route to correct screen on notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let type = response.notification.request.content.userInfo["type"] as? String ?? ""
        await MainActor.run {
            NotificationCenter.default.post(name: .nudgeLaunchType, object: type)
        }
    }
}

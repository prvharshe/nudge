---
title: Notification buttons and dated evening reminders
author: Pranav
date: 2026-11-05
branch: fix/notification-actions-evening-reminder
cost: { minutes: 29, tokens: 160457 }
touches:
  - ".codebase-memory/artifact.json"
  - ".codebase-memory/graph.db.zst"
  - NudgeWidget/CheckInIntent.swift
  - nudge.xcodeproj/project.pbxproj
  - nudge/Services/NotificationService.swift
  - nudge/Shared/RoutineStore.swift
  - nudge/Views/ContentView.swift
  - nudge/Views/FollowUpView.swift
  - nudge/Views/RoutinesView.swift
  - nudge/Views/SettingsView.swift
---

## Decided
- Evening check-in and follow-up are dated one-shots (14 days, follow-ups 2 days), not a repeating trigger, because iOS can't skip one day of a repeat. SharedStore.todayCheckIn is the cross-process "logged today" signal for app, widget and buttons.
- Button actions use the day in the notification's userInfo, never "now". Check-in buttons save locally with synced=false; upload waits for the next foreground so Health stats are not lost while locked.
- Backend auth was deferred by the user on Nov 5, 2026 because they may open the app widely and want proper auth then.

## Tried and ruled out
- Mutation tests showed the first race test proved nothing: it logged before the reschedule started. The race only reproduces when the button lands after `await Task.yield()` on an in-flight reschedule.
- Agent device access was off, so real button taps were not possible. A temporary uncommitted self-test built fake UNNotificationResponse objects through NSKeyedUnarchiver coders and KVC, and drove the real delegate.

## Watch out
- Launching the full Debug app in a simulator calls the production backend. Pass `-nudge.backendURL http://127.0.0.1:9` as a launch argument.
- Deleting an Entry while TodayDoneView shows it crashes with a SwiftData "detached from a context" error. Seen only in the test harness; Settings Reset may be worth checking.
- As of Nov 5, 2026 production Cloud Run has no RESEND_API_KEY or REPORT_EMAIL, so /api/report-email returns 503 and report cards are not being sent.
- Check-in reminders stop after 14 days without opening the app; there is no background refresh yet.

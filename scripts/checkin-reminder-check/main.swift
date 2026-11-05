// Self-check for CheckInReminders.plan (no XCTest target in this repo). Run from repo root:
// xcrun swiftc -o /tmp/crc nudge/Shared/SharedStore.swift nudge/Shared/RoutineStore.swift nudge/Shared/CheckInReminders.swift scripts/checkin-reminder-check/main.swift && /tmp/crc
import Foundation
var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
func d(_ s: String) -> Date { let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.dateFormat = "yyyy-MM-dd HH:mm"; return f.date(from: s)! }
func plan(at now: String, logged: Bool) -> [CheckInReminderPlan] {
    CheckInReminders.plan(eveningMinutes: 21 * 60, followUpMinutes: 22 * 60 + 30, loggedToday: logged, from: d(now), calendar: cal)
}

// Not logged, morning: today's evening + follow-up come first.
var p = plan(at: "2026-11-05 09:00", logged: false)
assert(p[0].fireDate == d("2026-11-05 21:00") && !p[0].isFollowUp, "first: \(p[0])")
assert(p[1].fireDate == d("2026-11-05 22:30") && p[1].isFollowUp, "second: \(p[1])")
assert(p[0].dayKey == "2026-11-05", p[0].dayKey)

// The bug this replaces: logging today must not silence tomorrow, even if the app is never reopened.
p = plan(at: "2026-11-05 09:00", logged: true)
assert(!p.contains { $0.dayKey == "2026-11-05" }, "logged today must stay silent")
assert(p[0].fireDate == d("2026-11-06 21:00"), "tomorrow still reminds: \(p[0])")
assert(p.filter { !$0.isFollowUp }.count == 13, "13 future evenings, got \(p.filter { !$0.isFollowUp }.count)")

// Times already passed are skipped.
p = plan(at: "2026-11-05 21:30", logged: false)
assert(p[0].fireDate == d("2026-11-05 22:30") && p[0].isFollowUp, "only follow-up left: \(p[0])")
p = plan(at: "2026-11-05 23:00", logged: false)
assert(p[0].fireDate == d("2026-11-06 21:00"), "nothing left today: \(p[0])")

// Ids are unique, day-scoped, and match what cancel(on:) removes.
p = plan(at: "2026-11-05 09:00", logged: false)
assert(Set(p.map(\.id)).count == p.count, "ids unique")
let todayIds = CheckInReminders.ids(on: d("2026-11-05 12:00"), calendar: cal)
assert(Set(p.filter { $0.dayKey == "2026-11-05" }.map(\.id)) == Set(todayIds), "cancel ids: \(todayIds)")
assert(p.allSatisfy { $0.id.hasPrefix(CheckInReminders.prefix) }, "prefix")

// Budget: routines (40) + these + morning + weekly digest must leave room under iOS's 64 pending limit.
assert(p.count == 16, "count \(p.count)")
assert(40 + p.count + 2 < 64, "over the pending limit")

// Sorted, and wall-clock time holds across a DST change (US fall-back 2026-11-01).
assert(p == p.sorted { $0.fireDate < $1.fireDate }, "sorted")
var ny = Calendar(identifier: .gregorian); ny.timeZone = TimeZone(identifier: "America/New_York")!
let f = DateFormatter(); f.calendar = ny; f.timeZone = ny.timeZone; f.dateFormat = "yyyy-MM-dd HH:mm"
let dst = CheckInReminders.plan(eveningMinutes: 21 * 60, followUpMinutes: 22 * 60 + 30, loggedToday: false, from: f.date(from: "2026-10-31 08:00")!, calendar: ny)
assert(f.string(from: dst.first { $0.dayKey == "2026-11-01" }!.fireDate) == "2026-11-01 21:00", "DST evening")

// A follow-up after midnight fires the next calendar day but still belongs to the evening before it.
let late = CheckInReminders.plan(eveningMinutes: 21 * 60, followUpMinutes: 30, loggedToday: false, from: d("2026-11-05 09:00"), calendar: cal)
let lateFollowUp = late.first { $0.isFollowUp }!
assert(lateFollowUp.fireDate == d("2026-11-06 00:30") && lateFollowUp.dayKey == "2026-11-05", "late follow-up: \(lateFollowUp)")
assert(late[0].fireDate == d("2026-11-05 21:00"), "evening still first: \(late[0])")
// Logging Nov 5 silences its after-midnight follow-up too.
let lateLogged = CheckInReminders.plan(eveningMinutes: 21 * 60, followUpMinutes: 30, loggedToday: true, from: d("2026-11-05 09:00"), calendar: cal)
assert(!lateLogged.contains { $0.dayKey == "2026-11-05" }, "logged day has no late follow-up")
assert(CheckInReminders.ids(on: d("2026-11-05 12:00"), calendar: cal).contains(lateFollowUp.id), "cancel(on:) reaches it")

print("check-in reminder tests passed")

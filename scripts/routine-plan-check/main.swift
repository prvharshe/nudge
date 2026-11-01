// Self-check for RoutineStore.plan (no XCTest target in this repo). Run from repo root:
// xcrun swiftc -o /tmp/rpc nudge/Shared/SharedStore.swift nudge/Shared/RoutineStore.swift scripts/routine-plan-check/main.swift && /tmp/rpc
import Foundation
var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
func d(_ s: String) -> Date { let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.dateFormat = "yyyy-MM-dd HH:mm"; return f.date(from: s)! }
let r = RoutineStore.defaultRoutines
assert(Set(r.map(\.id)).count == 5, "seed ids unique")
// 2026-11-02 is a Monday
let mon = d("2026-11-02 09:00")
let monItems = r.filter { $0.isScheduled(on: mon, calendar: cal) }.map(\.name)
assert(monItems == ["Hair Ras", "Hair Biotin", "Hair Ras", "Hair lotion"], "monday: \(monItems)")
let tue = r.filter { $0.isScheduled(on: d("2026-11-03 09:00"), calendar: cal) }.map(\.name)
assert(tue.contains("Hair oil, then wash") && !tue.contains("Hair lotion"), "tuesday: \(tue)")
// Plan for one day, nothing done: slots 10:00, 22:00, 23:30 → 3 due + 3 follow-ups
var p = RoutineStore.plan(routines: r, isDone: { _, _ in false }, from: mon, days: 1, calendar: cal)
assert(p.count == 6, "count \(p.count)")
assert(p[0].fireDate == d("2026-11-02 10:00") && p[0].title == "Time for Hair Ras + Hair Biotin", p[0].title)
assert(p[1].fireDate == d("2026-11-02 10:30") && p[1].id.hasSuffix("-f"))
assert(p.last!.fireDate == d("2026-11-03 00:00"), "lotion follow-up after midnight")
// Partially done slot only lists the open item
let ras = r[0].id
p = RoutineStore.plan(routines: r, isDone: { id, _ in id == ras }, from: mon, days: 1, calendar: cal)
assert(p[0].title == "Time for Hair Biotin", p[0].title)
// Whole 10:00 slot done → no 10:00 notifications; past times skipped, follow-up still pending
p = RoutineStore.plan(routines: r, isDone: { id, _ in id == ras || id == r[1].id }, from: mon, days: 1, calendar: cal)
assert(p.count == 4)
p = RoutineStore.plan(routines: r, isDone: { _, _ in false }, from: d("2026-11-02 10:10"), days: 1, calendar: cal)
assert(p.first!.fireDate == d("2026-11-02 10:30"), "only follow-up left for 10:00")
// 7-day plan stays under cap
assert(RoutineStore.plan(routines: r, isDone: { _, _ in false }, from: mon, calendar: cal).count <= 40)
assert(RoutineStore.dayKey(mon, calendar: cal) == "2026-11-02")
// DST: 10:00 must stay 10:00 local on the day clocks change (US fall-back 2026-11-01)
var ny = Calendar(identifier: .gregorian); ny.timeZone = TimeZone(identifier: "America/New_York")!
let f2 = DateFormatter(); f2.calendar = ny; f2.timeZone = ny.timeZone; f2.dateFormat = "yyyy-MM-dd HH:mm"
let dstDay = f2.date(from: "2026-11-01 08:00")!
assert(f2.string(from: r[0].time(on: dstDay, calendar: ny)) == "2026-11-01 10:00", "DST time \(f2.string(from: r[0].time(on: dstDay, calendar: ny)))")
let dp = RoutineStore.plan(routines: r, isDone: { _, _ in false }, from: dstDay, days: 1, calendar: ny)
assert(f2.string(from: dp[0].fireDate) == "2026-11-01 10:00", "DST fire")
// Full week of due reminders must survive the cap (follow-ups only near-term)
let week = RoutineStore.plan(routines: r, isDone: { _, _ in false }, from: mon, calendar: cal)
assert(week.filter { !$0.id.hasSuffix("-f") }.count == 7 * 2 + 2, "week due count \(week.filter { !$0.id.hasSuffix("-f") }.count)")
print("routine plan tests passed")

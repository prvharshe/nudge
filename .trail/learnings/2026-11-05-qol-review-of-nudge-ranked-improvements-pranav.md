---
title: "QOL review of nudge: ranked improvements, Nov 2026"
author: Pranav
date: 2026-11-05
branch: main
cost: { minutes: 4, tokens: 156011 }
touches:
  - ".codebase-memory/artifact.json"
  - ".codebase-memory/graph.db.zst"
---

## Decided
- List only, no app code changed. Do first: TodayDoneView crash with zero moved days (ContentView best-streak loop, `1..<sorted.count`), evening reminder removed by updateEveningForLoggedDay, widget pendingCheckIn dropped after midnight, past-day logging (CalendarView disables empty days; FollowUpView.entryDate has no caller), notification action buttons (none exist).
- Most of the Oct 31 audit's top fixes are done: recover-all removed, unsynced retry added, restore keeps the local day, deploy runs offline tests.

## Tried and ruled out
- Splitting the large view files (CoachView, CalendarView, BackendService): little user benefit, left out.
- The timezone date-shift on entry sync: iOS now sends calendarDate and test:dates passes, so it was not listed. Not checked on a device.

## Watch out
- Removing the repeating "evening-checkin" request stops future evenings too, until the next foreground re-adds it.
- Cold-launch notification routing (NotificationCenter post in NotificationDelegate) may race ContentView's onReceive. Read only, needs a device test.
- Deleting one entry needs backend work: restore brings the day back from its Supermemory doc.

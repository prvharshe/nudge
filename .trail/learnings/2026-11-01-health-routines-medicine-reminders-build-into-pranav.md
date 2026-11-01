---
title: "Health routines/medicine reminders: build into nudge, not separate app"
author: Pranav
date: 2026-11-01
branch: main
cost: { minutes: 1, tokens: 43813 }
touches:
  - ".codebase-memory/artifact.json"
  - ".codebase-memory/graph.db.zst"
---

## Decided
- Proposed (pending user answers): build medicine/hair-care reminders inside nudge as a general "Routines" feature, not a separate app. nudge is meant to grow into an all-health app (physical, mental, hair).
- Reuse what exists: the NudgeWidget extension and its interactive AppIntents (CheckInIntent.swift) for tap-to-tick, SharedStore for sharing data with the widget, and NotificationService.scheduleFollowUp's pattern for re-sending reminders until ticked.
- Planned UI: a medium home-screen + Lock Screen "today checklist" widget that shows only items due now.
## Tried and ruled out
- Separate app: would duplicate the widget target, the App Group store and the notification code.
- Apple Reminders: OK as a stopgap, but can't link a lotion night to the next-day oil/wash or re-send until done.
## Watch out
- Unverified: whether AlarmKit (iOS 26 alarm-style alerts) works on a free developer account. Check before relying on it.
- Open questions to the user: which two lotion nights, meal/bed times, and whether to build the general routines editor or only the hair routine first.

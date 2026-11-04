---
title: Auto-log unlogged days from Apple Health
author: Pranav
date: 2026-10-31
branch: main
cost: { minutes: 3, tokens: 73921 }
touches:
  - ".codebase-memory/artifact.json"
  - ".codebase-memory/graph.db.zst"
  - nudge/Services/HealthKitService.swift
  - nudge/Services/NotificationService.swift
  - nudge/Views/ContentView.swift
---

## Decided
- ContentView.autoLogMissedDays() fills the last 7 past days (never today) with no Entry, using HealthKitService.inferEntry(for:). It runs in .task after the restore check, and on every scenePhase .active.
- Rule: workout → moved (with the classify() tag); ≥4000 steps → moved ["walk"]; 1–3999 steps → didn't move; 0 steps and no workout → skip (no data ≠ didn't move).
- Auto entries look identical to manual ones (no flag, no note). NotificationService.notifyAutoLogged sends type "history", which routes to tab 1.

## Tried and ruled out
- Background auto-logging: there is no BGTask/HealthKit background-delivery setup; the .backgroundTask in nudgeApp is an empty stub. Foreground only for now.

## Watch out
- It must not run before checkForRecoverableHistory finishes (restoreCheckDone gate). Local entries suppress the cloud-restore prompt on a fresh install.
- No test target exists; the decision rule is a static func so it can be tested once one is added.

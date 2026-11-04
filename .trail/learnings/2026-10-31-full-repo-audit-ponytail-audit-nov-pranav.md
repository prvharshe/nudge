---
title: "Full repo audit (ponytail-audit), Nov 2026"
author: Pranav
date: 2026-10-31
branch: main
cost: { minutes: 2, tokens: 100248 }
touches:
  - ".codebase-memory/artifact.json"
  - ".codebase-memory/graph.db.zst"
---

## Decided
- Audit only, no code changed. Top fix order: (1) delete GET /api/entries/recover-all + scanAllEntries + Settings "Scan Supermemory" button — unauthenticated dump of all users' entries on a public Cloud Run URL (repo is public, URL in README); (2) add a launch-time retry for Entry.synced == false (nothing reads `synced` today); (3) restore date formatters parse yyyy-MM-dd in UTC then startOfDay locally -> one day early west of UTC (4 copies: ContentView + 3 in SettingsView).
- Supermemory helpers (restoreEntries, deleteAllEntries, checkUserHasEntries) use semantic search with limit caps (100 / 1), not full listing: coach "recent 14", restore and delete break past ~100 docs; /exists count is always 0 or 1.

## Tried and ruled out
- Recovery code is UUID-based, so it is strong enough; not a finding.
- In-memory nudge/learn caches grow unbounded but are fine at single-user load.

## Watch out
- searchMemories returns plain strings; reports.js reads m.content (always undefined), so report insights get no activity context and /reports/list (unused by iOS) returns empty summaries.
- Edited days create a second Supermemory doc; restore keeps whichever ranks first, not the newest.
- CI deploy workflow runs no tests; npm test and test:dates are offline and should gate deploys.
- There is no iOS test target.

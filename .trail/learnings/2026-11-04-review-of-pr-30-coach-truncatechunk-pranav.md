---
title: "Review of PR #30: Coach truncateChunk map bug"
author: Pranav
date: 2026-11-04
branch: feat/report-card-email
cost: { minutes: 1, tokens: 55139 }
touches:
  - ".codebase-memory/artifact.json"
  - ".codebase-memory/graph.db.zst"
  - nudge-backend/package.json
  - ".github/workflows/deploy-backend.yml"
---

## Decided
- PR #30 diagnosis is correct and the bug is still live on main (groq.js buildCoachMessages: recentEntries/semanticHits/profileMems .map(truncateChunk)). Array#map passes the index as truncateChunk's `max`, so Entry 1 becomes "…".
- Verified: PR's scripts/test-truncate-map.js fails on main ("Aug 07 must appear") and passes with the fix.
- Better root fix: drop truncateChunk's `max` param (no caller passes it) and use a constant, so point-free maps are safe.

## Tried and ruled out
- Other point-free maps in nudge-backend (snapshotToPromptLine, Number, Boolean) are safe: single-arg or harmless.

## Watch out
- PR branch is 16 commits behind main and conflicts in nudge-backend/package.json (main added test:report, test:restore).
- CI (.github/workflows/deploy-backend.yml) runs a fixed list of npm scripts; new test scripts must be added there or they never run.

---
title: Weekly/monthly habit report card emailed via Resend
author: Pranav
date: 2026-11-04
branch: feat/report-card-email
cost: { minutes: 11, tokens: 146228 }
touches:
  - ".codebase-memory/artifact.json"
  - ".codebase-memory/graph.db.zst"
  - nudge-backend/deploy-cloudrun.sh
  - nudge-backend/index.js
  - nudge-backend/package.json
  - nudge-backend/routes/reportEmail.js
  - nudge-backend/scripts/test-report-email.js
  - nudge-backend/services/reportEmail.js
  - nudge/Services/BackendService.swift
  - nudge/Services/HealthKitService.swift
---

## Decided
- Report data is gathered on the phone (ReportService.swift): routine ticks live only in App Group UserDefaults and steps only in HealthKit. The backend (services/reportEmail.js) does stats, grades and email-safe HTML; it's testable with `npm run test:report`, and iOS has no test target.
- Sends the last completed week and month, once each, from launch and foreground. A period is marked sent only after a 200, so failures (including a 503 when not configured) retry later. There's no BGTask.
- The recipient is fixed by the REPORT_EMAIL env var, never the request body, because the endpoint has no auth.
- Routine done-history retention is now 400 days (was 14).
## Tried and ruled out
- SVG/JS charts: Gmail strips them. All charts are tables with inline styles.
- Resend Idempotency-Key per period: the body can differ on retry (late step syncs), which may 409-block sends for 24h. Dropped; the worst case is one duplicate email.
## Watch out
- deploy-cloudrun.sh used --set-env-vars, which wipes other env vars. It's now --update-env-vars, so RESEND_API_KEY/REPORT_EMAIL survive deploys.
- Past days use today's routine list (shortcut comment in ReportService).
- validateReport must check nested fields: a throw from an async Express 4 handler crashes the process.

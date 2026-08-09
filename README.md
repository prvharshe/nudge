# Nudge

A personal movement coach for iOS. Nudge checks in with you every evening ("did you move today?"), remembers what you said, and greets you each morning with a short AI-generated nudge tailored to your recent activity. It also tracks streaks, trends, recovery, and health reports — all for a single user, with no accounts or sign-in.

## How it works

1. **9 PM check-in** — a local notification asks whether you moved today. You answer YES/NO, tag activities (walk, run, tired, busy, or custom), and optionally add a note.
2. **Entries are remembered** — each entry is stored locally with SwiftData and synced to the backend, which saves it to [Supermemory](https://supermemory.ai) tagged by your user ID.
3. **10 AM morning nudge** — the backend pulls your recent entries from Supermemory and asks Groq (`openai/gpt-oss-20b`) for a two-sentence personalized message.

## Repository layout

```
nudge/                  iOS app (SwiftUI + SwiftData)
  nudgeApp.swift        App entry, notification delegate & scheduling
  Models/               Entry, UserProfile, RecoveryScore, ActivityStore, MetricInfo
  Services/             Backend client, notifications, HealthKit, haptics, user ID
  Views/                Check-in flow, calendar, trends, coach chat, settings, onboarding
NudgeWidget/            Home-screen widget + check-in App Intent
nudge-backend/          Node.js + Express API
  routes/               entries, nudge, coach, reaction, weekly, memories, learn, reports, recovery
  services/             Supermemory client, Groq client, health-report parser
```

## Tech stack

- **iOS**: SwiftUI, SwiftData, WidgetKit, HealthKit, local notifications (no APNs — no paid developer account needed). Deployment target iOS 26.2, `MainActor` default isolation project-wide.
- **Backend**: Node.js (ESM) + Express. Supermemory for long-term memory, Groq for LLM generation, `pdf-parse`/`multer` for health-report uploads. Deployable to Cloud Run or Railway.

## Getting started

### Backend

```bash
cd nudge-backend
npm install
npm run dev          # starts on http://localhost:3000 (node --watch)
```

Create `nudge-backend/.env` with:

```
SUPERMEMORY_API_KEY=sk-...
GROQ_API_KEY=gsk_...
PORT=3000            # optional, defaults to 3000
# GROQ_CHAT_MODEL=openai/gpt-oss-20b   # optional; default is GPT OSS 20B
```

### iOS app

Open `nudge.xcodeproj` in Xcode (26.3+) and run on a simulator, or build from the CLI:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme nudge -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug build -project nudge.xcodeproj
```

There are no external Swift dependencies — it's a plain Xcode project.

**Pointing the app at your backend:** Release builds use the Cloud Run production URL (`https://nudge-backend-40994690021.asia-south1.run.app`). In Debug builds, set `nudge.backendURL` via Settings to point at `http://localhost:3000`, a LAN IP, or another deployed backend.

## API overview

All routes are mounted under `/api` and keyed by a per-install user UUID:

| Route | Purpose |
|---|---|
| `POST /api/entries` | Save an evening check-in to Supermemory |
| `GET /api/nudge` | Morning nudge (Supermemory context + Groq, cached daily) |
| `POST /api/coach` | Conversational coach chat |
| `POST /api/reaction` | Quick AI reaction after a check-in |
| `POST /api/weekly` | Weekly digest |
| `POST /api/memories` | Search stored memories (`/summarize-convo` condenses coach chats) |
| `POST /api/learn` | Teach the coach a fact about you |
| `POST /api/reports/upload` · `GET /api/reports/list` | Upload & parse health report PDFs |
| `POST /api/recovery/register` · `/restore` | Back up / restore the user ID across reinstalls |

## Notes

- **Single-user by design** — identity is a UUID generated on first launch and stored in UserDefaults (`nudge.userId`). Supermemory isolation is via tags `["nudge", userId]`.
- Advanced settings are gated behind an admin PIN.
- The widget supports checking in directly from the home screen and shows your streak.

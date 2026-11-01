# Routines (medicine & care reminders)

First step toward Nudge as an all-health app: user-defined reminders with a home-screen checklist.

## Behaviour
- A **Routine** = name, detail (dose/notes), time of day, weekdays (empty = every day).
- Seeded on first run with the Traya hair routine:
  - Hair Ras — 2 tablets after breakfast — daily 10:00
  - Hair Biotin — 1 tablet after breakfast — daily 10:00
  - Hair Ras — 2 tablets after dinner — daily 22:00
  - Hair lotion — before bed — Mon + Thu 23:30
  - Hair oil, then wash — Tue + Fri 10:00
- **Routines tab**: today's checklist (tap to tick/untick) + list of all routines (add / edit / delete).
- **Widget** (small, medium, large, Lock Screen rectangular): today's not-yet-done routines, overdue ones highlighted; tap the circle to tick without opening the app. Ticked items disappear.
- **Notifications**: one per time slot (routines at the same time grouped), plus a "still pending" follow-up 30 min later. Both are skipped once every routine in the slot is ticked. Scheduled one-shot for the next 7 days, refreshed on every app foreground and on every tick.

## Storage
App Group UserDefaults (`group.com.ph.nudge`) as JSON, so the widget can read and write it. Done-state is kept per day, pruned after 14 days. Not synced to the backend.

## Out of scope (v1)
AlarmKit full-screen alarms, "Mark done" action button on the notification, backend/coach awareness of routines, streaks/history for routines.

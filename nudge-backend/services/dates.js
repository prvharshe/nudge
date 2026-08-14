/**
 * Calendar-date helpers that avoid UTC midnight shifting the local day
 * (e.g. IST Aug 8 00:00 → Aug 7 when passed through ISO + toDateString).
 */

const DAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** True for YYYY-MM-DD. */
export function isCalendarDate(value) {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value);
}

/**
 * Format YYYY-MM-DD as "Sat Aug 08 2026" (legacy entry prefix shape).
 * Uses UTC noon so the calendar day is stable in any server timezone.
 */
export function formatCalendarDate(ymd) {
  if (!isCalendarDate(ymd)) return null;
  const [y, m, d] = ymd.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d, 12));
  const day = String(d).padStart(2, '0');
  return `${DAY_NAMES[dt.getUTCDay()]} ${MONTH_NAMES[dt.getUTCMonth()]} ${day} ${y}`;
}

/**
 * Best-effort calendar day for an entry POST body.
 * Prefer explicit calendarDate; fall back to ISO date only when it is already a date-only string.
 */
export function resolveEntryCalendarDate({ calendarDate, date } = {}) {
  if (isCalendarDate(calendarDate)) return calendarDate;
  if (isCalendarDate(date)) return date;
  if (typeof date === 'string' && date.length >= 10 && isCalendarDate(date.slice(0, 10))) {
    // ISO timestamps are UTC — do not use the YYYY-MM-DD prefix (that's the bug).
    return null;
  }
  return null;
}

/** Build the natural-language check-in line stored in / shown to the coach. */
export function formatEntryContent({
  calendarDate,
  date,
  didMove,
  activities = [],
  note,
  hkParts = '',
} = {}) {
  const ymd = resolveEntryCalendarDate({ calendarDate, date });
  const dateStr = ymd
    ? formatCalendarDate(ymd)
    : (date ? new Date(date).toDateString() : new Date().toDateString());
  const movementStr = didMove ? 'did move' : 'did not move';
  const activityStr = activities.length > 0 ? `Activities: ${activities.join(', ')}.` : '';
  const noteStr = note ? `Note: "${note}".` : '';
  return `On ${dateStr}, the user ${movementStr}. ${activityStr} ${noteStr} ${hkParts}`
    .trim()
    .replace(/\s+/g, ' ');
}

/** Turn a restored entry snapshot into the same prompt line shape. */
export function snapshotToPromptLine(entry) {
  return formatEntryContent({
    calendarDate: entry.date,
    didMove: entry.didMove,
    activities: entry.activities ?? [],
    note: entry.note,
  });
}

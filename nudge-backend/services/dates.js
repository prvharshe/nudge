/**
 * Calendar-date helpers that avoid UTC midnight shifting the local day
 * (e.g. IST Aug 8 00:00 → Aug 7 when passed through ISO + toDateString).
 */

const DAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const DAY_NAMES_LONG = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const PROMPT_DAY_RE = /^(Sun|Mon|Tue|Wed|Thu|Fri|Sat) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{1,2}) (\d{4})$/;

function utcNoon(ymd) {
  const [y, m, d] = ymd.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d, 12));
}

function pad2(n) {
  return String(n).padStart(2, '0');
}

/** UTC YYYY-MM-DD — only a fallback when the device did not send calendarDate. */
export function utcTodayYmd(now = new Date()) {
  return `${now.getUTCFullYear()}-${pad2(now.getUTCMonth() + 1)}-${pad2(now.getUTCDate())}`;
}

/**
 * Shift a YYYY-MM-DD by `days` (negative = past) using UTC noon so IST/UTC
 * midnight cannot roll the calendar day.
 */
export function shiftCalendarDate(ymd, days) {
  if (!isCalendarDate(ymd)) return null;
  const dt = utcNoon(ymd);
  dt.setUTCDate(dt.getUTCDate() + days);
  return `${dt.getUTCFullYear()}-${pad2(dt.getUTCMonth() + 1)}-${pad2(dt.getUTCDate())}`;
}

/** Whole days from `fromYmd` to `toYmd` (positive if toYmd is later). */
export function daysBetween(fromYmd, toYmd) {
  if (!isCalendarDate(fromYmd) || !isCalendarDate(toYmd)) return null;
  return Math.round((utcNoon(toYmd) - utcNoon(fromYmd)) / 86400000);
}

/** Most recent occurrence of `weekdayIndex` (0=Sun) strictly before today. */
export function lastWeekdayYmd(todayYmd, weekdayIndex) {
  if (!isCalendarDate(todayYmd) || weekdayIndex < 0 || weekdayIndex > 6) return null;
  for (let i = 1; i <= 7; i++) {
    const ymd = shiftCalendarDate(todayYmd, -i);
    if (utcNoon(ymd).getUTCDay() === weekdayIndex) return ymd;
  }
  return null;
}

/** Parse "Thu Sep 10 2026" (entry prefix) into YYYY-MM-DD. */
export function parsePromptDay(value) {
  if (typeof value !== 'string') return null;
  const match = value.trim().match(PROMPT_DAY_RE);
  if (!match) return null;
  const month = MONTH_NAMES.indexOf(match[2]) + 1;
  return `${match[4]}-${pad2(month)}-${pad2(Number(match[3]))}`;
}

/** YYYY-MM-DD from "On Thu Sep 10 2026, the user..." */
export function calendarDateFromEntry(entry) {
  if (typeof entry !== 'string') return null;
  const match = entry.match(/^On (.+?),/);
  if (!match) return null;
  return parsePromptDay(match[1]);
}

/**
 * Exact meanings of "yesterday" / "last Thursday" relative to the device day.
 * When today is Thursday, last Thursday is 7 days ago — never a Thursday from weeks ago.
 */
export function relativeDateFacts(todayYmd) {
  if (!isCalendarDate(todayYmd)) return null;
  const lastWeekday = {};
  for (let i = 0; i < 7; i++) {
    lastWeekday[DAY_NAMES[i]] = lastWeekdayYmd(todayYmd, i);
  }
  return {
    todayYmd,
    todayLabel: formatCalendarDate(todayYmd),
    yesterdayYmd: shiftCalendarDate(todayYmd, -1),
    yesterdayLabel: formatCalendarDate(shiftCalendarDate(todayYmd, -1)),
    lastWeekday,
  };
}

/** Glossary injected into Groq prompts so relative weekday phrases are grounded. */
export function formatRelativeDateBlock(todayYmd) {
  const facts = relativeDateFacts(todayYmd);
  if (!facts) return '';
  const lines = [
    `Device calendar day: ${facts.todayLabel} (${facts.todayYmd}).`,
    'Relative phrases — use only when an entry prefix matches them exactly:',
    `- yesterday = ${facts.yesterdayLabel} (${facts.yesterdayYmd})`,
  ];
  for (let i = 0; i < 7; i++) {
    const ymd = facts.lastWeekday[DAY_NAMES[i]];
    lines.push(`- last ${DAY_NAMES_LONG[i]} = ${formatCalendarDate(ymd)} (${ymd})`);
  }
  return lines.join('\n');
}

/**
 * Age label for one check-in vs today. Older same-weekdays are explicitly
 * "not last Thursday" so the model cannot collapse them into that phrase.
 */
export function relativeAgeLabel(entryYmd, todayYmd) {
  const delta = daysBetween(entryYmd, todayYmd);
  if (delta == null) return null;
  if (delta === 0) return 'today';
  if (delta === 1) return 'yesterday';
  if (delta < 0) return `${-delta} days in the future`;

  const entryDow = utcNoon(entryYmd).getUTCDay();
  const weekdayLong = DAY_NAMES_LONG[entryDow];
  const lastThat = lastWeekdayYmd(todayYmd, entryDow);
  if (entryYmd === lastThat) {
    return delta === 1 ? 'yesterday' : `${delta} days ago (this is last ${weekdayLong})`;
  }
  return `${delta} days ago — not last ${weekdayLong}`;
}

/** Prefix a stored entry line with computed age for the model. */
export function annotateEntryForPrompt(entry, todayYmd) {
  const ymd = calendarDateFromEntry(entry);
  if (!ymd || !isCalendarDate(todayYmd)) return entry;
  const age = relativeAgeLabel(ymd, todayYmd);
  return `[${ymd}, ${age}] ${entry}`;
}

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

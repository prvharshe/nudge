#!/usr/bin/env node
/**
 * Unit checks for calendar-date helpers (no API keys required).
 */
import {
  annotateEntryForPrompt,
  calendarDateFromEntry,
  formatCalendarDate,
  formatEntryContent,
  formatRelativeDateBlock,
  isCalendarDate,
  lastWeekdayYmd,
  relativeAgeLabel,
  resolveEntryCalendarDate,
  snapshotToPromptLine,
} from '../services/dates.js';

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

assert(isCalendarDate('2026-08-08'), 'YYYY-MM-DD should be valid');
assert(!isCalendarDate('2026-08-07T18:30:00Z'), 'ISO timestamp is not a calendar date');

assert(
  resolveEntryCalendarDate({ calendarDate: '2026-08-08', date: '2026-08-07T18:30:00Z' }) === '2026-08-08',
  'calendarDate wins over ISO date'
);
assert(
  resolveEntryCalendarDate({ date: '2026-08-07T18:30:00Z' }) === null,
  'ISO-only must not be treated as a calendar day (TZ shift bug)'
);

assert(formatCalendarDate('2026-08-08') === 'Sat Aug 08 2026', `got ${formatCalendarDate('2026-08-08')}`);

const istShiftedIso = '2026-08-07T18:30:00Z'; // local Aug 8 IST midnight
assert(istShiftedIso.slice(0, 10) === '2026-08-07', 'UTC ISO day of IST midnight Aug 8 is Aug 7');

const fixed = formatEntryContent({
  calendarDate: '2026-08-08',
  date: istShiftedIso,
  didMove: true,
  activities: ['walk'],
  note: 'went out for the movies and roamed around',
});
assert(fixed.includes('Aug 08'), `fixed content should keep Aug 08: ${fixed}`);
assert(fixed.includes('movies'), 'note should be preserved');

const line = snapshotToPromptLine({
  date: '2026-08-07',
  didMove: true,
  activities: ['walk'],
  note: 'went out for the movies and roamed around',
});
assert(line.startsWith('On Fri Aug 07 2026,'), `snapshot line: ${line}`);

const today = '2026-09-17'; // Thursday
assert(lastWeekdayYmd(today, 4) === '2026-09-10', 'last Thursday from Thu 17 Sep is 10 Sep');
assert(relativeAgeLabel('2026-09-17', today) === 'today', 'today');
assert(relativeAgeLabel('2026-09-16', today) === 'yesterday', 'yesterday');
assert(
  relativeAgeLabel('2026-09-10', today) === '7 days ago (this is last Thursday)',
  `last Thursday label: ${relativeAgeLabel('2026-09-10', today)}`
);
assert(
  relativeAgeLabel('2026-08-27', today) === '21 days ago — not last Thursday',
  `older Thursday must not be last Thursday: ${relativeAgeLabel('2026-08-27', today)}`
);

const oldWalk = formatEntryContent({
  calendarDate: '2026-08-27',
  didMove: true,
  activities: ['walk'],
  hkParts: 'Workout: 38-minute Walk.',
});
assert(calendarDateFromEntry(oldWalk) === '2026-08-27', `parse ${oldWalk}`);
const annotated = annotateEntryForPrompt(oldWalk, today);
assert(annotated.startsWith('[2026-08-27, 21 days ago — not last Thursday]'), annotated);

const glossary = formatRelativeDateBlock(today);
assert(glossary.includes('last Thursday = Thu Sep 10 2026 (2026-09-10)'), glossary);
assert(!glossary.includes('2026-08-27'), 'glossary must not treat Aug 27 as last Thursday');

console.log('All calendar-date checks passed.');

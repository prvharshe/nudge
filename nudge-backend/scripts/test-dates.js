#!/usr/bin/env node
/**
 * Unit checks for calendar-date helpers (no API keys required).
 */
import {
  formatCalendarDate,
  formatEntryContent,
  isCalendarDate,
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
const legacyBug = `On ${new Date(istShiftedIso).toDateString()}, the user did move.`;
assert(legacyBug.includes('Aug 07'), `expected legacy bug shape, got ${legacyBug}`);

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

console.log('All calendar-date checks passed.');

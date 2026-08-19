#!/usr/bin/env node
/**
 * Regression: Array#map must not pass the index into truncateChunk as `max`
 * (that wiped Entry 1 to "…" and made Coach claim missing check-ins).
 */
import { buildCoachMessages } from '../services/groq.js';

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

const recent = [
  'On Thu Aug 13 2026, the user did move. Activities: walk.',
  'On Fri Aug 07 2026, the user did move. Activities: walk. Note: "went out for the movies and roamed around".',
  'On Sun Aug 02 2026, the user did move. Activities: walk. Note: "night walk in drizzle".',
];

const system = buildCoachMessages(recent, 'check for august 7')[0].content;

assert(system.includes('Aug 07'), 'Aug 07 must appear in coach system prompt');
assert(system.includes('movies'), 'movies note must appear in coach system prompt');
assert(!/^Entry 1: …$/m.test(system), 'Entry 1 must not be wiped to ellipsis');
assert(system.includes('Entry 1: On Thu Aug 13 2026'), 'Entry 1 should keep full newest check-in');

console.log('truncate-map regression checks passed.');

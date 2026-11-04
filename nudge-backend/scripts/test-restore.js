#!/usr/bin/env node
/**
 * Checks for the Supermemory record → restored entry mapping (no API keys required).
 */
import assert from 'node:assert/strict';
import { recordsToEntries, restoreEntries } from '../services/supermemory.js';

const legacy = {
  content: 'On Thu Sep 10 2026, the user did move. Activities: walk, run. Note: "hi".',
  metadata: { tags: ['nudge', 'u1', 'entry'] },
  createdAt: '2026-09-10T20:00:00.000Z',
};
const snapshot = {
  content: 'On Fri Sep 11 2026, the user did not move.',
  metadata: { tags: ['nudge', 'u1', 'entry'], nudgeEntry: { date: '2026-09-08', didMove: false, activities: [], note: null } },
  createdAt: '2026-09-08T20:00:00.000Z',
};
// Two copies of the same day (an edit posts a new document); the newer one must win
// regardless of the order the API returns them in.
const editedOld = {
  content: '',
  metadata: { nudgeEntry: { date: '2026-09-12', didMove: false, activities: [], note: 'old' } },
  createdAt: '2026-09-12T20:00:00.000Z',
};
const editedNew = {
  content: '',
  metadata: { nudgeEntry: { date: '2026-09-12', didMove: true, activities: ['walk'], note: 'new' } },
  createdAt: '2026-09-13T08:00:00.000Z',
};
const junk = { content: 'Profile: likes running', metadata: {} };

assert.deepEqual(recordsToEntries([legacy]), [
  { date: '2026-09-10', didMove: true, activities: ['walk', 'run'], note: 'hi' },
], 'legacy text entry');

assert.deepEqual(recordsToEntries([snapshot]), [
  { date: '2026-09-08', didMove: false, activities: [], note: null },
], 'metadata snapshot wins over content text');

for (const order of [[editedOld, editedNew], [editedNew, editedOld]]) {
  const out = recordsToEntries(order);
  assert.equal(out.length, 1, 'one entry per date');
  assert.equal(out[0].note, 'new', 'newest copy per date must win');
}

assert.deepEqual(
  recordsToEntries([editedNew, junk, legacy, snapshot, editedOld]).map(e => e.date),
  ['2026-09-08', '2026-09-10', '2026-09-12'],
  'sorted oldest→newest, unparseable records dropped'
);

// restoreEntries pages through /v3/documents/list until totalPages (stubbed fetch, no network).
const pages = { 1: [editedOld, legacy], 2: [editedNew, snapshot] };
const bodies = [];
globalThis.fetch = async (url, init) => {
  const body = JSON.parse(init.body);
  bodies.push(body);
  assert.match(url, /\/v3\/documents\/list$/);
  return { ok: true, json: async () => ({ memories: pages[body.page], pagination: { currentPage: body.page, totalPages: 2 } }) };
};
assert.deepEqual((await restoreEntries('u1')).map(e => [e.date, e.note]), [
  ['2026-09-08', null], ['2026-09-10', 'hi'], ['2026-09-12', 'new'],
], 'restoreEntries reads every page');
assert.deepEqual(bodies.map(b => b.page), [1, 2]);
assert.deepEqual(bodies[0].filters, { AND: [
  { filterType: 'array_contains', key: 'tags', value: 'u1' },
  { filterType: 'array_contains', key: 'tags', value: 'entry' },
] });
assert.equal(bodies[0].includeContent, true);

console.log('All restore-mapping checks passed.');

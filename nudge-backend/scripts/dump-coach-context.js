#!/usr/bin/env node
/**
 * Dump chronological + semantic coach context for a userId (or UUID prefix).
 * Requires SUPERMEMORY_API_KEY.
 *
 *   SUPERMEMORY_API_KEY=... node scripts/dump-coach-context.js BC0C4DEC
 *   SUPERMEMORY_API_KEY=... node scripts/dump-coach-context.js <full-uuid> "check for august 7"
 */
import { restoreEntries, searchMemories } from '../services/supermemory.js';
import { snapshotToPromptLine } from '../services/dates.js';

const prefixOrId = (process.argv[2] || '').trim();
const question = (process.argv[3] || 'check for august 7').trim();

if (!prefixOrId) {
  console.error('Usage: dump-coach-context.js <userId-or-prefix> [question]');
  process.exit(1);
}
if (!process.env.SUPERMEMORY_API_KEY) {
  console.error('SUPERMEMORY_API_KEY is required');
  process.exit(1);
}

async function resolveUserId(input) {
  if (input.length >= 36) return input;
  // Prefix: scan nudge entries and match tag.
  const res = await fetch('https://api.supermemory.ai/v3/search', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${process.env.SUPERMEMORY_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      q: 'movement check-in activity note movies',
      filters: {
        AND: [
          { filterType: 'array_contains', key: 'tags', value: 'nudge' },
          { filterType: 'array_contains', key: 'tags', value: 'entry' },
        ],
      },
      limit: 100,
    }),
  });
  if (!res.ok) throw new Error(`search failed: ${res.status} ${await res.text()}`);
  const data = await res.json();
  const needle = input.toLowerCase();
  const ids = new Set();
  for (const r of data.results ?? []) {
    const tags = r.metadata?.tags ?? [];
    for (const t of tags) {
      if (typeof t === 'string' && t.toLowerCase().startsWith(needle) && t.includes('-')) {
        ids.add(t);
      }
    }
  }
  if (ids.size === 0) throw new Error(`No userId tags starting with ${input}`);
  if (ids.size > 1) {
    console.error('Multiple matches:', [...ids]);
    throw new Error('Ambiguous prefix');
  }
  return [...ids][0];
}

const userId = await resolveUserId(prefixOrId);
console.log('userId:', userId);

const restored = await restoreEntries(userId);
const recent = restored.slice(-14).reverse().map(snapshotToPromptLine);
const semantic = await searchMemories(userId, 8, question, 'entry');

console.log('\n=== Restored snapshots (all) ===');
for (const e of restored) {
  console.log(`${e.date} moved=${e.didMove} activities=${JSON.stringify(e.activities)} note=${JSON.stringify(e.note)}`);
}

console.log('\n=== Coach recentEntries (newest 14) ===');
recent.forEach((line, i) => console.log(`${i + 1}. ${line}`));

console.log(`\n=== Semantic hits for: ${JSON.stringify(question)} ===`);
semantic.forEach((line, i) => console.log(`${i + 1}. ${line}`));

const hasAug7 = [...recent, ...semantic].some(l => /Aug 0?7/i.test(l) || /2026-08-07/.test(l));
const hasAug8 = [...recent, ...semantic].some(l => /Aug 0?8/i.test(l) || /2026-08-08/.test(l));
const hasMovies = [...recent, ...semantic].some(l => /movies/i.test(l));
console.log('\n=== Presence in coach context ===');
console.log({ hasAug7, hasAug8, hasMovies, recentCount: recent.length, semanticCount: semantic.length });

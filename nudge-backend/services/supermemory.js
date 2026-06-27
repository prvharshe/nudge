const BASE = 'https://api.supermemory.ai/v3';

function headers() {
  return {
    'Authorization': `Bearer ${process.env.SUPERMEMORY_API_KEY}`,
    'Content-Type': 'application/json',
  };
}

/**
 * Store any memory in Supermemory with a type tag.
 * type: 'entry' | 'profile' | 'insight' | 'milestone' | 'convo' | 'context'
 */
export async function addMemory(content, userId, type = 'entry', extraTags = [], extraMetadata = {}) {
  const res = await fetch(`${BASE}/documents`, {
    method: 'POST',
    headers: headers(),
    body: JSON.stringify({
      content,
      metadata: { tags: ['nudge', userId, type, ...extraTags], ...extraMetadata },
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Supermemory addMemory failed (${res.status}): ${text}`);
  }
  return res.json();
}

/** Backward compat alias */
export const addEntry = (content, userId) => addMemory(content, userId, 'entry');

/**
 * Search memories for a user.
 * @param {string}      userId  User UUID
 * @param {number}      limit   Max results
 * @param {string}      query   Semantic search query
 * @param {string|null} type    If set, filter to only this memory type tag
 */
export async function searchMemories(userId, limit = 14, query = 'movement exercise activity rest day', type = null) {
  const andFilters = [
    { filterType: 'array_contains', key: 'tags', value: userId },
  ];
  if (type) {
    andFilters.push({ filterType: 'array_contains', key: 'tags', value: type });
  }

  const res = await fetch(`${BASE}/search`, {
    method: 'POST',
    headers: headers(),
    body: JSON.stringify({
      q: query,
      filters: { AND: andFilters },
      limit,
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Supermemory searchMemories failed (${res.status}): ${text}`);
  }

  const data = await res.json();
  return (data.results ?? [])
    .map(r => r.chunks?.[0]?.content ?? r.content ?? '')
    .filter(Boolean);
}

/** Backward compat alias — searches all memory types */
export const searchEntries = (userId, limit = 14, query = 'movement exercise activity rest day') =>
  searchMemories(userId, limit, query);

/**
 * Delete all Supermemory memories for a user (all types).
 * Uses two different queries to ensure all memory types are caught.
 */
export async function deleteAllEntries(userId) {
  const filter = { AND: [{ filterType: 'array_contains', key: 'tags', value: userId }] };

  const [res1, res2] = await Promise.all([
    fetch(`${BASE}/search`, {
      method: 'POST',
      headers: headers(),
      body: JSON.stringify({ q: 'movement exercise activity rest day', filters: filter, limit: 100 }),
    }),
    fetch(`${BASE}/search`, {
      method: 'POST',
      headers: headers(),
      body: JSON.stringify({ q: 'profile insight milestone coaching context convo', filters: filter, limit: 100 }),
    }),
  ]);

  const data1 = res1.ok ? await res1.json() : { results: [] };
  const data2 = res2.ok ? await res2.json() : { results: [] };

  const seen = new Set();
  const documentIds = [...(data1.results ?? []), ...(data2.results ?? [])]
    .map(r => r.documentId)
    .filter(id => id && !seen.has(id) && seen.add(id));

  if (documentIds.length === 0) return { deleted: 0, failed: 0 };

  let deleted = 0, failed = 0;
  const chunks = [];
  for (let i = 0; i < documentIds.length; i += 10) chunks.push(documentIds.slice(i, i + 10));

  for (const chunk of chunks) {
    const results = await Promise.allSettled(
      chunk.map(id =>
        fetch(`${BASE}/documents/${id}`, { method: 'DELETE', headers: headers() })
      )
    );
    for (const r of results) {
      if (r.status === 'fulfilled' && (r.value.status === 204 || r.value.status === 200)) deleted++;
      else failed++;
    }
  }

  return { deleted, failed };
}

/**
 * Lightweight check if user has any entry memories in Supermemory.
 * Returns { hasEntries: boolean, count: number, latestDate: string|null }
 */
export async function checkUserHasEntries(userId) {
  const filter = { AND: [
    { filterType: 'array_contains', key: 'tags', value: userId },
    { filterType: 'array_contains', key: 'tags', value: 'entry' }
  ]};
  const res = await fetch(`${BASE}/search`, {
    method: 'POST',
    headers: headers(),
    body: JSON.stringify({ q: 'movement', filters: filter, limit: 1 }),
  });
  if (!res.ok) return { hasEntries: false, count: 0, latestDate: null };
  const data = await res.json();
  const results = data.results ?? [];
  return {
    hasEntries: results.length > 0,
    count: results.length,
    latestDate: results[0]?.metadata?.nudgeEntry?.date ?? null
  };
}

async function searchRawMemories(filters, query, limit = 100) {
  const res = await fetch(`${BASE}/search`, {
    method: 'POST',
    headers: headers(),
    body: JSON.stringify({ q: query, filters: { AND: filters }, limit }),
  });
  if (!res.ok) return [];
  return (await res.json()).results ?? [];
}

function legacyDateKey(value) {
  const match = value.match(/^(?:Sun|Mon|Tue|Wed|Thu|Fri|Sat) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{1,2}) (\d{4})$/);
  if (!match) return null;
  const month = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'].indexOf(match[1]) + 1;
  return `${match[3]}-${String(month).padStart(2, '0')}-${match[2].padStart(2, '0')}`;
}

/**
 * Scan ALL nudge-tagged documents from Supermemory (no userId filter).
 * Returns every entry-type document. Use as a last-resort recovery.
 */
export async function scanAllEntries() {
  const records = await searchRawMemories([
    { filterType: 'array_contains', key: 'tags', value: 'nudge' },
    { filterType: 'array_contains', key: 'tags', value: 'entry' },
  ], 'movement check-in activity note steps workout', 100);

  const seen = new Set();
  return records.map(record => {
    const content = record.chunks?.[0]?.content ?? record.content ?? '';
    const snapshot = record.metadata?.nudgeEntry;
    if (snapshot?.date && typeof snapshot.didMove === 'boolean') return snapshot;

    const match = content.match(/^On (.+?), the user (did move|did not move)\.\s*(?:Activities: (.*?)\.\s*)?(?:Note: "(.*?)"\.)?/);
    if (!match) return null;
    const date = legacyDateKey(match[1]);
    if (!date) return null;
    return {
      date,
      didMove: match[2] === 'did move',
      activities: match[3] ? match[3].split(', ').filter(Boolean) : [],
      note: match[4] || null,
    };
  }).filter(entry => {
    if (!entry || seen.has(entry.date)) return false;
    seen.add(entry.date);
    return true;
  }).sort((a, b) => a.date.localeCompare(b.date));
}

export async function restoreEntries(userId) {
  const records = await searchRawMemories([
    { filterType: 'array_contains', key: 'tags', value: userId },
    { filterType: 'array_contains', key: 'tags', value: 'entry' },
  ], 'movement check-in activity note steps workout', 100);

  const seen = new Set();
  return records.map(record => {
    const content = record.chunks?.[0]?.content ?? record.content ?? '';
    const snapshot = record.metadata?.nudgeEntry;
    if (snapshot?.date && typeof snapshot.didMove === 'boolean') return snapshot;

    const match = content.match(/^On (.+?), the user (did move|did not move)\.\s*(?:Activities: (.*?)\.\s*)?(?:Note: "(.*?)"\.)?/);
    if (!match) return null;
    const date = legacyDateKey(match[1]);
    if (!date) return null;
    return {
      date,
      didMove: match[2] === 'did move',
      activities: match[3] ? match[3].split(', ').filter(Boolean) : [],
      note: match[4] || null,
    };
  }).filter(entry => {
    if (!entry || seen.has(entry.date)) return false;
    seen.add(entry.date);
    return true;
  }).sort((a, b) => a.date.localeCompare(b.date));
}

/**
 * Register a recovery code for a user.
 * Stores { kind: 'nudge-recovery-v1', userId } tagged with 'recovery' and a hash of the code.
 * The code hash tag allows finding the userId later without knowing the userId itself.
 */
export async function registerRecoveryCode(userId, recoveryCode) {
  const hash = await codeHash(recoveryCode);
  return addMemory(JSON.stringify({ kind: 'nudge-recovery-v1', userId }), userId, 'recovery', [hash]);
}

/**
 * Find a userId by recovery code.
 * Searches for recovery memories tagged with the code hash,
 * then extracts the userId from the stored JSON.
 */
export async function recoverUserId(recoveryCode) {
  const hash = await codeHash(recoveryCode);
  const records = await searchRawMemories([
    { filterType: 'array_contains', key: 'tags', value: 'recovery' },
    { filterType: 'array_contains', key: 'tags', value: hash },
  ], 'nudge recovery account', 10);
  for (const record of records) {
    const content = record.chunks?.[0]?.content ?? record.content ?? '';
    try {
      const userId = JSON.parse(content).userId;
      if (typeof userId === 'string' && userId.length > 0) return userId;
    } catch {}
  }
  return null;
}

async function codeHash(code) {
  const { createHash } = await import('node:crypto');
  return createHash('sha256').update(code.trim().toUpperCase()).digest('hex');
}

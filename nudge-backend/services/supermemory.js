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
    signal: AbortSignal.timeout(8000),
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

/** Search only dated check-in entries (excludes insights, convos, profile, etc.) */
export const searchEntries = (userId, limit = 14, query = 'movement exercise activity rest day') =>
  searchMemories(userId, limit, query, 'entry');

/**
 * List every document whose metadata.tags contains all of `tags`.
 * Uses POST /v3/documents/list (https://supermemory.ai/docs/api-reference/documents/list-documents):
 * its `filters` takes the same QueryFilter as /v3/search (array_contains on metadata keys), and it
 * pages with page/limit (limit max 1100) until pagination.totalPages. Unlike /v3/search it is not
 * capped by relevance and returns createdAt/updatedAt per document.
 */
async function listAllDocuments(tags, includeContent = false) {
  const docs = [];
  for (let page = 1; ; page++) {
    const res = await fetch(`${BASE}/documents/list`, {
      method: 'POST',
      headers: headers(),
      body: JSON.stringify({
        filters: { AND: tags.map(value => ({ filterType: 'array_contains', key: 'tags', value })) },
        includeContent,
        limit: 500,
        page,
        sort: 'createdAt',
        order: 'desc',
      }),
      signal: AbortSignal.timeout(15000),
    });
    if (!res.ok) {
      throw new Error(`Supermemory listDocuments failed (${res.status}): ${await res.text()}`);
    }
    const data = await res.json();
    docs.push(...(data.memories ?? []));
    if (page >= (data.pagination?.totalPages ?? 0)) return docs;
  }
}

/** Delete all Supermemory memories for a user (all types). */
export async function deleteAllEntries(userId) {
  const documentIds = (await listAllDocuments([userId])).map(d => d.id).filter(Boolean);

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
 * Check if user has any entry memories in Supermemory.
 * Returns { hasEntries: boolean, count: number, latestDate: string|null }
 */
export async function checkUserHasEntries(userId) {
  const entries = await restoreEntries(userId);
  return {
    hasEntries: entries.length > 0,
    count: entries.length,
    latestDate: entries.at(-1)?.date ?? null,
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

export async function restoreEntries(userId) {
  return recordsToEntries(await listAllDocuments([userId, 'entry'], true));
}

/**
 * Maps Supermemory entry documents to { date, didMove, activities, note }, one per date, oldest→newest.
 * Editing a day posts a new document, so the newest copy (by createdAt) of each date wins.
 */
export function recordsToEntries(records) {
  const seen = new Set();
  const newestFirst = [...records].sort((a, b) => String(b.createdAt ?? '').localeCompare(String(a.createdAt ?? '')));
  return newestFirst.map(record => {
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

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
export async function addMemory(content, userId, type = 'entry') {
  const res = await fetch(`${BASE}/documents`, {
    method: 'POST',
    headers: headers(),
    body: JSON.stringify({
      content,
      metadata: { tags: ['nudge', userId, type] },
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

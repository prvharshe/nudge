const BASE = 'https://api.supermemory.ai/v3';

function headers() {
  return {
    'Authorization': `Bearer ${process.env.SUPERMEMORY_API_KEY}`,
    'Content-Type': 'application/json',
  };
}

/**
 * Store a movement entry in Supermemory for this user.
 * @param {string} content  Natural-language description of the entry
 * @param {string} userId   UUID identifying the user
 */
export async function addEntry(content, userId) {
  const res = await fetch(`${BASE}/documents`, {
    method: 'POST',
    headers: headers(),
    body: JSON.stringify({
      content,
      metadata: {
        tags: ['nudge', userId],
      },
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Supermemory addEntry failed (${res.status}): ${text}`);
  }

  return res.json();
}

/**
 * Retrieve recent movement entries for this user.
 * @param {string} userId   UUID identifying the user
 * @param {number} limit    Max entries to return (default 14)
 * @returns {string[]}      Array of content strings, newest first
 */
export async function searchEntries(userId, limit = 14) {
  const res = await fetch(`${BASE}/search`, {
    method: 'POST',
    headers: headers(),
    body: JSON.stringify({
      q: 'movement exercise activity rest day',
      filters: {
        AND: [
          { filterType: 'array_contains', key: 'tags', value: userId },
        ],
      },
      limit,
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Supermemory searchEntries failed (${res.status}): ${text}`);
  }

  const data = await res.json();
  // v3 returns { results: [{ chunks: [{ content }], ... }] }
  const results = data.results ?? [];
  return results
    .map((r) => r.chunks?.[0]?.content ?? r.content ?? '')
    .filter(Boolean);
}

/**
 * Delete all Supermemory entries for a user.
 * Fetches every document tagged with userId, then deletes each one.
 * @param {string} userId   UUID identifying the user
 * @returns {{ deleted: number, failed: number }}
 */
export async function deleteAllEntries(userId) {
  // 1. Fetch all document IDs for this user (Supermemory max limit is 100)
  const searchRes = await fetch(`${BASE}/search`, {
    method: 'POST',
    headers: headers(),
    body: JSON.stringify({
      q: 'movement exercise activity rest day',
      filters: {
        AND: [
          { filterType: 'array_contains', key: 'tags', value: userId },
        ],
      },
      limit: 100,
    }),
  });

  if (!searchRes.ok) {
    const text = await searchRes.text();
    throw new Error(`Supermemory search before delete failed (${searchRes.status}): ${text}`);
  }

  const data = await searchRes.json();
  const documentIds = (data.results ?? []).map((r) => r.documentId).filter(Boolean);

  if (documentIds.length === 0) return { deleted: 0, failed: 0 };

  // 2. Delete each document (in parallel, max 10 at a time to avoid rate limits)
  let deleted = 0;
  let failed = 0;

  const chunks = [];
  for (let i = 0; i < documentIds.length; i += 10) {
    chunks.push(documentIds.slice(i, i + 10));
  }

  for (const chunk of chunks) {
    const results = await Promise.allSettled(
      chunk.map((id) =>
        fetch(`${BASE}/documents/${id}`, {
          method: 'DELETE',
          headers: headers(),
        })
      )
    );
    for (const r of results) {
      if (r.status === 'fulfilled' && (r.value.status === 204 || r.value.status === 200)) {
        deleted++;
      } else {
        failed++;
      }
    }
  }

  return { deleted, failed };
}

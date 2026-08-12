import express from 'express';
import { searchMemories } from '../services/supermemory.js';
import { generateCoachAnswer, streamCoachAnswer } from '../services/groq.js';
import { endSse, initSse, sendSse } from '../services/sse.js';

const router = express.Router();

/** Supermemory search that degrades gracefully instead of failing the whole coach call. */
async function safeSearch(userId, limit, query, type) {
  if (!process.env.SUPERMEMORY_API_KEY) {
    return [];
  }
  try {
    return await searchMemories(userId, limit, query, type);
  } catch (err) {
    console.warn(`coach memory search failed (${type ?? 'all'}):`, err.message);
    return [];
  }
}

async function loadCoachContext(userId, question) {
  const q = question.trim();
  const [recentEntries, semanticHits, profileMems, keptInsights] = await Promise.all([
    safeSearch(userId, 14, 'movement exercise activity rest day check-in', 'entry'),
    safeSearch(userId, 8, q, 'entry'),
    safeSearch(userId, 1, 'user profile fitness goals', 'profile'),
    safeSearch(userId, 3, q, 'insight'),
  ]);
  return { q, recentEntries, semanticHits, profileMems, keptInsights };
}

/**
 * POST /api/coach
 * Body: { userId, question, history?, goal?, profileSummary? }
 *
 * Dual retrieval:
 *   1. Recent dated check-ins (type: entry) — chronological primary context
 *   2. Limited semantic entry hits tuned to the question
 *   3. Profile memory (always)
 *   4. User-kept advice (type: insight) — high-signal anchors the user chose to save
 * Auto-summarized convos are excluded so old summaries don't drown recent check-ins.
 */
router.post('/', async (req, res) => {
  const { userId, question, history, goal, profileSummary } = req.body;

  if (!userId || !question?.trim()) {
    return res.status(400).json({ error: 'userId and question are required' });
  }

  const conversationHistory = Array.isArray(history)
    ? history.slice(-10).filter(m => m.role && m.content)
    : [];

  try {
    const { q, recentEntries, semanticHits, profileMems, keptInsights } =
      await loadCoachContext(userId, question);

    const answer = await generateCoachAnswer(
      recentEntries,
      q,
      conversationHistory,
      goal || null,
      profileSummary || null,
      profileMems,
      semanticHits,
      keptInsights
    );
    res.json({ answer });
  } catch (err) {
    console.error('coach error:', err.message);
    const isRateLimit = err?.status === 429 || /rate limit/i.test(err?.message ?? '');
    if (isRateLimit) {
      return res.status(503).json({ error: 'Coach is busy right now. Wait a moment and try again.' });
    }
    res.status(500).json({ error: 'Failed to generate answer' });
  }
});

/**
 * POST /api/coach/stream
 * Same body as /api/coach. Responds with text/event-stream:
 *   event: meta   — retrieval started / ready
 *   event: token  — { text } content deltas
 *   event: error  — { error }
 *   event: done   — [DONE]
 */
router.post('/stream', async (req, res) => {
  const { userId, question, history, goal, profileSummary } = req.body ?? {};

  if (!userId || !question?.trim()) {
    return res.status(400).json({ error: 'userId and question are required' });
  }

  const conversationHistory = Array.isArray(history)
    ? history.slice(-10).filter(m => m.role && m.content)
    : [];

  initSse(res);
  sendSse(res, 'meta', { stage: 'retrieving' });

  // Abort upstream work if the client disconnects.
  // Use `aborted`, not `req.close` — Node emits `close` on IncomingMessage when
  // the POST body is fully read, which would otherwise kill the stream early.
  let closed = false;
  req.on('aborted', () => {
    closed = true;
  });
  res.on('close', () => {
    if (!res.writableEnded) closed = true;
  });

  try {
    const { q, recentEntries, semanticHits, profileMems, keptInsights } =
      await loadCoachContext(userId, question);

    if (closed) return;

    sendSse(res, 'meta', {
      stage: 'generating',
      sources: {
        recentEntries: recentEntries.length,
        semanticHits: semanticHits.length,
        profile: profileMems.length,
        keeps: keptInsights.length,
      },
    });

    let tokenCount = 0;
    for await (const text of streamCoachAnswer(
      recentEntries,
      q,
      conversationHistory,
      goal || null,
      profileSummary || null,
      profileMems,
      semanticHits,
      keptInsights
    )) {
      if (closed) break;
      tokenCount += 1;
      sendSse(res, 'token', { text });
    }

    if (!closed) {
      sendSse(res, 'meta', { stage: 'complete', tokenEvents: tokenCount });
      endSse(res);
    }
  } catch (err) {
    console.error('coach stream error:', err.message);
    if (!closed && !res.writableEnded) {
      const isRateLimit = err?.status === 429 || /rate limit/i.test(err?.message ?? '');
      sendSse(res, 'error', {
        error: isRateLimit
          ? 'Coach is busy right now. Wait a moment and try again.'
          : 'Failed to generate answer',
      });
      endSse(res);
    }
  }
});

/**
 * GET /api/coach/sse-probe?intervalMs=400&count=5
 * Timed SSE ticks with no LLM dependency — used to detect proxy buffering
 * (Cloud Run / CDN). If ticks arrive ~intervalMs apart, streaming is unbuffered.
 */
router.get('/sse-probe', (req, res) => {
  const intervalMs = Math.min(2000, Math.max(100, Number(req.query.intervalMs) || 400));
  const count = Math.min(20, Math.max(2, Number(req.query.count) || 5));

  initSse(res);
  sendSse(res, 'meta', { stage: 'probe', intervalMs, count });

  let i = 0;
  const timer = setInterval(() => {
    i += 1;
    sendSse(res, 'tick', { i, t: Date.now() });
    if (i >= count) {
      clearInterval(timer);
      endSse(res);
    }
  }, intervalMs);

  req.on('close', () => clearInterval(timer));
});

export default router;

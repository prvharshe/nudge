import { Router } from 'express';
import { searchEntries } from '../services/supermemory.js';
import { generateNudge } from '../services/groq.js';

const router = Router();

// Simple in-memory cache: one nudge per user per day
const cache = new Map(); // key: `${userId}-${YYYY-MM-DD}`, value: string

function todayKey(userId) {
  const today = new Date().toISOString().slice(0, 10);
  return `${userId}-${today}`;
}

/**
 * GET /api/nudge?userId=...&refresh=true
 *
 * Returns a personalised 2-sentence morning nudge using recent Supermemory entries.
 * Cached per user per day to avoid burning Groq credits.
 * Pass refresh=true to bypass the cache (e.g. after fixing a bad nudge).
 */
router.get('/', async (req, res) => {
  const { userId, refresh, userName } = req.query;

  if (!userId) {
    return res.status(400).json({ error: 'userId is required' });
  }

  const key = todayKey(userId);
  if (cache.has(key) && refresh !== 'true') {
    return res.json({ message: cache.get(key), cached: true });
  }

  try {
    const entries = await searchEntries(userId, 14);
    const message = await generateNudge(entries, userName || 'friend');
    cache.set(key, message);
    res.json({ message });
  } catch (err) {
    console.error('[nudge] Error generating nudge:', err.message);
    res.status(500).json({
      message: 'Keep going — every day counts.',
      error: err.message,
    });
  }
});

export default router;

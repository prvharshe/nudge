import { Router } from 'express';
import { generateLearnInsight } from '../services/groq.js';

const router = Router();

// Per-user per-day cache
const cache = new Map(); // key: `${userId}-${YYYY-MM-DD}`

function todayKey(userId) {
  return `${userId}-${new Date().toISOString().slice(0, 10)}`;
}

/**
 * POST /api/learn
 * Body: { userId, restingHR?, hrv?, sleepHours?, steps?, recoveryScore?,
 *         recoveryLabel?, goal?, profileSummary? }
 *
 * Returns a single educational health insight paragraph (3–4 sentences)
 * grounded in the user's actual metrics for today.
 * Cached once per user per day.
 */
router.post('/', async (req, res) => {
  const {
    userId,
    restingHR, hrv, sleepHours, steps,
    recoveryScore, recoveryLabel,
    goal, profileSummary,
    refresh,
  } = req.body;

  if (!userId) {
    return res.status(400).json({ error: 'userId is required' });
  }

  const key = todayKey(userId);
  if (cache.has(key) && refresh !== true) {
    return res.json({ insight: cache.get(key), cached: true });
  }

  const metrics = { restingHR, hrv, sleepHours, steps, recoveryScore, recoveryLabel, goal };

  try {
    const insight = await generateLearnInsight(metrics, profileSummary || null);
    cache.set(key, insight);
    res.json({ insight });
  } catch (err) {
    console.error('[learn] Error generating insight:', err.message);
    res.status(500).json({ error: 'Failed to generate insight' });
  }
});

export default router;

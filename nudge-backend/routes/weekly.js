import express from 'express';
import { searchEntries } from '../services/supermemory.js';
import { generateWeeklyInsight } from '../services/groq.js';

const router = express.Router();

/**
 * POST /api/weekly
 * Body: { userId }
 * Returns: { insight }
 *
 * Fetches recent check-in entries (type: entry only), sorts/filters by date
 * inside generateWeeklyInsight. Caching is handled client-side.
 * Weekly insights are NOT written back to Supermemory — that created a
 * feedback loop where old summaries polluted coach/weekly retrieval.
 */
router.post('/', async (req, res) => {
  const { userId, goal, profileSummary } = req.body;

  if (!userId) {
    return res.status(400).json({ error: 'userId is required' });
  }

  try {
    const entries = await searchEntries(userId, 30);
    const insight = await generateWeeklyInsight(entries, goal || null, profileSummary || null);
    res.json({ insight });
  } catch (err) {
    console.error('weekly insight error:', err.message);
    res.status(500).json({ error: 'Failed to generate weekly insight' });
  }
});

export default router;

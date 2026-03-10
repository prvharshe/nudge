import express from 'express';
import { searchEntries } from '../services/supermemory.js';
import { generateWeeklyInsight } from '../services/groq.js';

const router = express.Router();

/**
 * POST /api/weekly
 * Body: { userId }
 * Returns: { insight }
 *
 * Fetches up to 30 recent entries and generates a 3-sentence
 * weekly pattern analysis. Caching is handled client-side.
 */
router.post('/', async (req, res) => {
  const { userId } = req.body;

  if (!userId) {
    return res.status(400).json({ error: 'userId is required' });
  }

  try {
    const entries = await searchEntries(userId, 30);
    const insight = await generateWeeklyInsight(entries);
    res.json({ insight });
  } catch (err) {
    console.error('weekly insight error:', err.message);
    res.status(500).json({ error: 'Failed to generate weekly insight' });
  }
});

export default router;

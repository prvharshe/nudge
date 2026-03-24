import express from 'express';
import { searchEntries } from '../services/supermemory.js';
import { generateReaction } from '../services/groq.js';

const router = express.Router();

/**
 * POST /api/reaction
 * Body: { userId, didMove, activities }
 * Returns: { reaction }
 *
 * Generates a single-sentence coach reaction to a just-logged entry,
 * using recent Supermemory history for context.
 */
router.post('/', async (req, res) => {
  const { userId, didMove, activities = [], goal, profileSummary } = req.body;

  if (!userId || didMove === undefined) {
    return res.status(400).json({ error: 'userId and didMove are required' });
  }

  try {
    const entries = await searchEntries(userId, 10);
    const reaction = await generateReaction(entries, didMove, activities, goal || null, profileSummary || null);
    res.json({ reaction });
  } catch (err) {
    console.error('reaction error:', err.message);
    res.status(500).json({ error: 'Failed to generate reaction' });
  }
});

export default router;

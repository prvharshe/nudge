import express from 'express';
import { searchMemories } from '../services/supermemory.js';
import { generateCoachAnswer } from '../services/groq.js';

const router = express.Router();

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
    const q = question.trim();
    const [recentEntries, semanticHits, profileMems, keptInsights] = await Promise.all([
      searchMemories(userId, 14, 'movement exercise activity rest day check-in', 'entry'),
      searchMemories(userId, 8, q, 'entry'),
      searchMemories(userId, 1, 'user profile fitness goals', 'profile'),
      searchMemories(userId, 3, q, 'insight'),
    ]);

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
    res.status(500).json({ error: 'Failed to generate answer' });
  }
});

export default router;

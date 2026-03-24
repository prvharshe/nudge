import express from 'express';
import { searchMemories } from '../services/supermemory.js';
import { generateCoachAnswer } from '../services/groq.js';

const router = express.Router();

/**
 * POST /api/coach
 * Body: { userId, question, history?, goal?, profileSummary? }
 *
 * Runs two parallel Supermemory searches:
 *   1. Semantic search with the question → entries + insights + milestones + context + convos
 *   2. Targeted profile fetch → always include profile regardless of question
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
    const [entries, profileMems] = await Promise.all([
      searchMemories(userId, 20, question.trim()),                          // all types, question-tuned
      searchMemories(userId, 1, 'user profile fitness goals', 'profile'),   // always fetch profile
    ]);

    const answer = await generateCoachAnswer(
      entries,
      question.trim(),
      conversationHistory,
      goal || null,
      profileSummary || null,
      profileMems
    );
    res.json({ answer });
  } catch (err) {
    console.error('coach error:', err.message);
    res.status(500).json({ error: 'Failed to generate answer' });
  }
});

export default router;

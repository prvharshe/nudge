import express from 'express';
import { searchEntries } from '../services/supermemory.js';
import { generateCoachAnswer } from '../services/groq.js';

const router = express.Router();

/**
 * POST /api/coach
 * Body: { userId: string, question: string }
 * Returns: { answer: string }
 *
 * Uses the user's question as a semantic search query against Supermemory,
 * so the most *relevant* entries (not just most recent) inform the answer.
 */
router.post('/', async (req, res) => {
  const { userId, question, history, goal } = req.body;

  if (!userId || !question?.trim()) {
    return res.status(400).json({ error: 'userId and question are required' });
  }

  // Normalise history: array of {role, content} pairs, capped at last 10 turns
  const conversationHistory = Array.isArray(history)
    ? history.slice(-10).filter(m => m.role && m.content)
    : [];

  try {
    // Semantic search: use the question itself as the query to surface relevant entries
    const entries = await searchEntries(userId, 20, question.trim());
    const answer = await generateCoachAnswer(entries, question.trim(), conversationHistory, goal || null);
    res.json({ answer });
  } catch (err) {
    console.error('coach error:', err.message);
    res.status(500).json({ error: 'Failed to generate answer' });
  }
});

export default router;

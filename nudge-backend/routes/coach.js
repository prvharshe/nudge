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
  const { userId, question } = req.body;

  if (!userId || !question?.trim()) {
    return res.status(400).json({ error: 'userId and question are required' });
  }

  try {
    // Semantic search: use the question itself as the query to surface relevant entries
    const entries = await searchEntries(userId, 20, question.trim());
    const answer = await generateCoachAnswer(entries, question.trim());
    res.json({ answer });
  } catch (err) {
    console.error('coach error:', err.message);
    res.status(500).json({ error: 'Failed to generate answer' });
  }
});

export default router;

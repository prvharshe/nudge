import { Router } from 'express';
import { addMemory } from '../services/supermemory.js';
import { summarizeConversation } from '../services/groq.js';

const router = Router();
const VALID_TYPES = new Set(['profile', 'insight', 'milestone', 'convo', 'context']);

/**
 * POST /api/memories
 * Body: { userId, type, content }
 * Stores any typed memory in Supermemory.
 */
router.post('/', async (req, res) => {
  const { userId, type, content } = req.body;
  if (!userId || !type || !content) {
    return res.status(400).json({ error: 'userId, type, and content are required' });
  }
  if (!VALID_TYPES.has(type)) {
    return res.status(400).json({ error: `Invalid type. Valid: ${[...VALID_TYPES].join(', ')}` });
  }
  try {
    await addMemory(content, userId, type);
    res.json({ ok: true });
  } catch (err) {
    console.error('[memories]', err.message);
    res.json({ ok: false, error: err.message });
  }
});

/**
 * POST /api/memories/summarize-convo
 * Body: { userId, messages: [{role, content}] }
 * Summarises a coach conversation via Groq and stores it as a 'convo' memory.
 */
router.post('/summarize-convo', async (req, res) => {
  const { userId, messages } = req.body;
  if (!userId || !Array.isArray(messages) || messages.length < 2) {
    return res.status(400).json({ error: 'userId and messages (min 2) are required' });
  }
  try {
    const summary = await summarizeConversation(messages);
    if (!summary) return res.json({ ok: false, reason: 'empty summary' });
    const today = new Date().toDateString();
    const content = `[Coach conversation on ${today}] ${summary}`;
    await addMemory(content, userId, 'convo');
    res.json({ ok: true, summary });
  } catch (err) {
    console.error('[memories/summarize-convo]', err.message);
    res.json({ ok: false, error: err.message });
  }
});

export default router;

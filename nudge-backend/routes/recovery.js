import { Router } from 'express';
import { recoverUserId, registerRecoveryCode } from '../services/supermemory.js';

const router = Router();

router.post('/register', async (req, res) => {
  const { userId, recoveryCode } = req.body;
  if (!userId || !recoveryCode) return res.status(400).json({ error: 'userId and recoveryCode are required' });
  try {
    await registerRecoveryCode(userId, recoveryCode);
    res.json({ ok: true });
  } catch (err) {
    console.error('[recovery] Register error:', err.message);
    res.status(500).json({ error: 'Could not register recovery code' });
  }
});

router.post('/restore', async (req, res) => {
  const { recoveryCode } = req.body;
  if (!recoveryCode) return res.status(400).json({ error: 'recoveryCode is required' });
  try {
    const userId = await recoverUserId(recoveryCode);
    if (!userId) return res.status(404).json({ error: 'Recovery code not found' });
    res.json({ userId });
  } catch (err) {
    console.error('[recovery] Restore error:', err.message);
    res.status(500).json({ error: 'Could not restore account' });
  }
});

export default router;

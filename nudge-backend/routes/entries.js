import { Router } from 'express';
import { formatEntryContent, resolveEntryCalendarDate } from '../services/dates.js';
import { addMemory, deleteAllEntries, checkUserHasEntries, restoreEntries, scanAllEntries } from '../services/supermemory.js';

const router = Router();

/**
 * POST /api/entries
 * Body: { userId, calendarDate?, date, didMove, activities[], note? }
 *
 * Stores the evening check-in entry in Supermemory as natural language.
 * Prefer calendarDate (YYYY-MM-DD, local day on device) so UTC ISO midnights
 * do not shift the logged day (e.g. IST Aug 8 → Aug 7).
 */
router.post('/', async (req, res) => {
  const { userId, calendarDate, date, didMove, activities = [], note, steps, workoutMinutes, calories, workoutType, sleepHours, restingHR, hrv, foodCalories, protein, carbs, fat } = req.body;

  if (!userId || typeof didMove !== 'boolean') {
    return res.status(400).json({ error: 'userId and didMove are required' });
  }

  const hkParts = [
    steps != null         ? `Steps: ${Number(steps).toLocaleString()}.` : '',
    workoutType && workoutMinutes ? `Workout: ${workoutMinutes}-minute ${workoutType}.` : '',
    calories != null      ? `Active calories: ${calories}.` : '',
    sleepHours != null    ? `Sleep the night before: ${Number(sleepHours).toFixed(1)} hours.` : '',
    restingHR != null     ? `Resting heart rate: ${restingHR} BPM.` : '',
    hrv != null           ? `HRV: ${hrv}ms.` : '',
    foodCalories != null ? `Food intake: ${foodCalories} kcal.` : '',
    protein != null      ? `Protein: ${protein}g.` : '',
    carbs != null        ? `Carbs: ${carbs}g.` : '',
    fat != null          ? `Fat: ${fat}g.` : '',
  ].filter(Boolean).join(' ');

  const ymd = resolveEntryCalendarDate({ calendarDate, date });
  const content = formatEntryContent({
    calendarDate: ymd,
    date,
    didMove,
    activities,
    note,
    hkParts,
  });

  const snapshot = ymd
    ? { date: ymd, didMove, activities, note: note || null }
    : null;

  try {
    await addMemory(content, userId, 'entry', [], snapshot ? { nudgeEntry: snapshot } : {});
    res.json({ ok: true });
  } catch (err) {
    console.error('[entries] Supermemory error:', err.message);
    // Still HTTP 200 so flaky SM does not spin the client — body.ok is false.
    // Clients must check ok before marking the entry synced.
    res.json({ ok: false, error: err.message });
  }
});

/**
 * GET /api/entries?userId=...
 *
 * Returns all entries for a user, for restoring history on reinstall.
 */
router.get('/', async (req, res) => {
  const { userId } = req.query;
  if (!userId) return res.status(400).json({ error: 'userId is required' });
  try {
    const entries = await restoreEntries(userId);
    res.json({ entries });
  } catch (err) {
    console.error('[entries] Restore error:', err.message);
    res.status(500).json({ error: 'Could not restore entries' });
  }
});

/**
 * DELETE /api/entries?userId=...
 *
 * Permanently deletes all Supermemory entries for this user.
 * Called from the app's "Delete AI Memory" settings action.
 */
router.delete('/', async (req, res) => {
  const { userId } = req.query;

  if (!userId) {
    return res.status(400).json({ error: 'userId is required' });
  }

  try {
    const result = await deleteAllEntries(userId);
    console.log(`[entries] Deleted Supermemory data for ${userId}:`, result);
    res.json({ ok: true, ...result });
  } catch (err) {
    console.error('[entries] Delete error:', err.message);
    res.status(500).json({ ok: false, error: err.message });
  }
});

/**
 * GET /api/entries/recover-all
 *
 * Last-resort recovery: scans ALL nudge entries in Supermemory
 * without requiring a userId. Returns everything found.
 */
router.get('/recover-all', async (req, res) => {
  try {
    const entries = await scanAllEntries();
    res.json({ entries });
  } catch (err) {
    console.error('[entries] Recover-all error:', err.message);
    res.status(500).json({ error: 'Could not scan entries' });
  }
});

/**
 * GET /api/entries/exists?userId=...
 *
 * Lightweight check if user has any entries in Supermemory.
 * Returns { hasEntries: boolean, count: number, latestDate: string|null }
 */
router.get('/exists', async (req, res) => {
  const { userId } = req.query;
  if (!userId) return res.status(400).json({ error: 'userId is required' });
  try {
    const result = await checkUserHasEntries(userId);
    res.json(result);
  } catch (err) {
    console.error('[entries] Exists check error:', err.message);
    res.status(500).json({ error: 'Could not check entries' });
  }
});

export default router;

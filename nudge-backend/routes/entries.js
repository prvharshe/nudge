import { Router } from 'express';
import { addEntry, deleteAllEntries } from '../services/supermemory.js';

const router = Router();

/**
 * POST /api/entries
 * Body: { userId, date, didMove, activities[], note? }
 *
 * Stores the evening check-in entry in Supermemory as natural language.
 */
router.post('/', async (req, res) => {
  const { userId, date, didMove, activities = [], note, steps, workoutMinutes, calories, workoutType, sleepHours, restingHR, hrv, foodCalories, protein, carbs, fat } = req.body;

  if (!userId || typeof didMove !== 'boolean') {
    return res.status(400).json({ error: 'userId and didMove are required' });
  }

  // Format as natural language for Supermemory
  const dateStr = date ? new Date(date).toDateString() : new Date().toDateString();
  const movementStr = didMove ? 'did move' : 'did not move';
  const activityStr = activities.length > 0
    ? `Activities: ${activities.join(', ')}.`
    : '';
  const noteStr = note ? `Note: "${note}".` : '';

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

  const content = `On ${dateStr}, the user ${movementStr}. ${activityStr} ${noteStr} ${hkParts}`.trim().replace(/\s+/g, ' ');

  try {
    await addEntry(content, userId);
    res.json({ ok: true });
  } catch (err) {
    console.error('[entries] Supermemory error:', err.message);
    // Return 200 anyway so the iOS app doesn't retry indefinitely
    res.json({ ok: false, error: err.message });
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

export default router;

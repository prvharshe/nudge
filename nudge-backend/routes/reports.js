import { Router } from 'express';
import multer from 'multer';
import { extractReportText } from '../services/reportParser.js';
import { extractBiomarkers, generateReportInsights } from '../services/groq.js';
import { addMemory, searchMemories } from '../services/supermemory.js';

const router = Router();

// Store file in memory only — we never persist the raw PDF on disk
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 15 * 1024 * 1024 }, // 15MB max
  fileFilter: (req, file, cb) => {
    const allowed = ['application/pdf', 'image/jpeg', 'image/png', 'image/heic', 'image/webp'];
    if (allowed.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Only PDF and image files are supported'));
    }
  },
});

/**
 * POST /api/reports/upload
 * Multipart form: file (PDF/image), userId, optional hkMetrics JSON string
 *
 * Returns: { insights: string[], biomarkers: object, reportDate: string, summary: string }
 */
router.post('/upload', upload.single('file'), async (req, res) => {
  const { userId, hkMetrics: hkMetricsRaw, profileSummary } = req.body;

  if (!userId) return res.status(400).json({ error: 'userId is required' });
  if (!req.file) return res.status(400).json({ error: 'No file uploaded' });

  let hkMetrics = {};
  try { hkMetrics = hkMetricsRaw ? JSON.parse(hkMetricsRaw) : {}; } catch { /* ignore */ }

  try {
    // 1. Extract raw text from the file
    const rawText = await extractReportText(req.file.buffer, req.file.mimetype);
    if (!rawText || rawText.length < 30) {
      return res.status(422).json({ error: 'Could not extract readable text from the file. Try a clearer image or a text-based PDF.' });
    }

    // 2. Parse into structured biomarkers
    const biomarkers = await extractBiomarkers(rawText);

    // 3. Build a text summary of the report for Supermemory
    const today = new Date().toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' });
    const bioLines = Object.values(biomarkers)
      .map(b => `${b.name}: ${b.value}${b.unit ? ' ' + b.unit : ''} (${b.status})`)
      .join(', ');
    const memorySummary = `[Health Report uploaded on ${today}] ${bioLines || rawText.slice(0, 400)}`;

    // 4. Store in Supermemory as 'report' type (non-blocking)
    addMemory(memorySummary, userId, 'report').catch(err =>
      console.error('[reports] Supermemory store failed:', err.message)
    );

    // 5. Fetch recent activity memories for context
    let memories = [];
    try {
      const result = await searchMemories(userId, 8, 'movement sleep recovery activity');
      memories = result.map(m => m.content ?? '').filter(Boolean);
    } catch { /* proceed without */ }

    // 6. Generate personalised insights
    const insights = await generateReportInsights(biomarkers, hkMetrics, memories, profileSummary ?? null);

    res.json({
      ok: true,
      insights,
      biomarkers,
      reportDate: today,
      summary: memorySummary,
    });
  } catch (err) {
    console.error('[reports/upload]', err.message);
    res.status(500).json({ error: err.message || 'Failed to process report' });
  }
});

/**
 * GET /api/reports/list?userId=xxx
 * Returns metadata about past uploaded reports stored in Supermemory.
 */
router.get('/list', async (req, res) => {
  const { userId } = req.query;
  if (!userId) return res.status(400).json({ error: 'userId is required' });

  try {
    const results = await searchMemories(userId, 20, 'health report uploaded', 'report');
    const reports = results.map((m, i) => ({
      id: i,
      summary: m.content?.slice(0, 120) ?? '',
      date: m.createdAt ?? null,
    }));
    res.json({ reports });
  } catch (err) {
    console.error('[reports/list]', err.message);
    res.json({ reports: [] });
  }
});

export default router;

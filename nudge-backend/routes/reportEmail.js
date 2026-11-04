import express from 'express';
import { renderReportEmail, validateReport } from '../services/reportEmail.js';

const router = express.Router();

/**
 * POST /api/report-email
 * Body: { userId, report }  (shape documented in services/reportEmail.js)
 * Emails the rendered report card via Resend.
 *
 * Recipient comes from the REPORT_EMAIL env var, never the request body, so this
 * unauthenticated endpoint can't be used to email arbitrary addresses.
 */
router.post('/', async (req, res) => {
  const { userId, report } = req.body ?? {};
  if (!userId) return res.status(400).json({ error: 'userId is required' });
  try {
    validateReport(report);
  } catch (err) {
    return res.status(400).json({ error: err.message });
  }

  const apiKey = process.env.RESEND_API_KEY;
  const to = process.env.REPORT_EMAIL;
  if (!apiKey || !to) {
    // 503 so the app keeps the report pending and retries on a later launch.
    return res.status(503).json({ error: 'Report email is not configured' });
  }

  try {
    const { subject, html } = renderReportEmail(report);
    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: process.env.REPORT_FROM || 'Nudge <onboarding@resend.dev>',
        to: [to],
        subject,
        html,
      }),
    });
    if (!r.ok) {
      console.error('report-email resend error:', r.status, await r.text());
      return res.status(502).json({ error: 'Email provider rejected the report' });
    }
    res.json({ ok: true });
  } catch (err) {
    console.error('report-email error:', err.message);
    res.status(502).json({ error: 'Failed to send report email' });
  }
});

export default router;

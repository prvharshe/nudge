#!/usr/bin/env node
/**
 * Smoke-tests the production (or BASE_URL) coach API path that the iOS app uses.
 * Exit 0 on success; non-zero with a clear message on failure.
 */
const BASE = (process.env.BASE_URL || 'https://nudge-backend-40994690021.asia-south1.run.app')
  .replace(/\/$/, '');

async function request(path, { method = 'GET', body } = {}) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: body ? { 'Content-Type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* non-JSON */ }
  return { status: res.status, text, json };
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function main() {
  console.log(`Smoke testing coach against ${BASE}`);

  const health = await request('/api/health');
  assert(health.status === 200, `health expected 200, got ${health.status}: ${health.text.slice(0, 200)}`);
  assert(health.json?.status === 'ok', `health payload missing status=ok: ${health.text.slice(0, 200)}`);
  console.log('✓ GET /api/health');

  const invalid = await request('/api/coach', { method: 'POST', body: {} });
  assert(invalid.status === 400, `invalid coach expected 400, got ${invalid.status}`);
  console.log('✓ POST /api/coach rejects empty body');

  const coach = await request('/api/coach', {
    method: 'POST',
    body: {
      userId: 'smoke-test-user',
      question: 'What patterns do you see in my data?',
      history: [],
    },
  });
  assert(coach.status === 200, `coach expected 200, got ${coach.status}: ${coach.text.slice(0, 300)}`);
  assert(typeof coach.json?.answer === 'string' && coach.json.answer.length > 0,
    `coach missing answer: ${coach.text.slice(0, 300)}`);
  console.log('✓ POST /api/coach returns answer');
  console.log(`  answer preview: ${coach.json.answer.slice(0, 120)}…`);
  console.log('All smoke checks passed.');
}

main().catch((err) => {
  console.error('Smoke test failed:', err.message);
  process.exit(1);
});

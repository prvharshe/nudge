#!/usr/bin/env node
/**
 * Verify SSE end-to-end against BASE_URL (local or Cloud Run).
 *
 * Checks:
 *  1) /api/coach/sse-probe — timed ticks arrive without proxy buffering
 *  2) /api/coach/stream   — Groq token events arrive progressively (needs GROQ on server)
 *
 * Exit 0 only if all requested checks pass.
 *
 * Usage:
 *   BASE_URL=http://127.0.0.1:3000 node scripts/verify-sse.js
 *   BASE_URL=https://…run.app SKIP_COACH=1 node scripts/verify-sse.js   # probe only
 */
const BASE = (process.env.BASE_URL || 'http://127.0.0.1:3000').replace(/\/$/, '');
const SKIP_COACH = process.env.SKIP_COACH === '1';
const INTERVAL_MS = Number(process.env.PROBE_INTERVAL_MS || 400);
const COUNT = Number(process.env.PROBE_COUNT || 5);
/** Max allowed skew vs expected tick spacing before we call it "buffered". */
const BUFFER_TOLERANCE_MS = Number(process.env.BUFFER_TOLERANCE_MS || 250);
/** If all ticks arrive in a burst shorter than this fraction of expected span → buffered. */
const BURST_RATIO = 0.45;

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

/**
 * Read an SSE response body, recording wall-clock arrival for each event.
 * @returns {Promise<{ events: Array<{event: string, data: string, at: number}>, headers: Headers, status: number }>}
 */
async function readSse(path, { method = 'GET', body } = {}) {
  const started = Date.now();
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: body
      ? { 'Content-Type': 'application/json', Accept: 'text/event-stream' }
      : { Accept: 'text/event-stream' },
    body: body ? JSON.stringify(body) : undefined,
  });

  const contentType = res.headers.get('content-type') || '';
  assert(res.status === 200, `${path} expected 200, got ${res.status}`);
  assert(
    contentType.includes('text/event-stream'),
    `${path} expected text/event-stream, got ${contentType || '(none)'}`
  );

  const events = [];
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let currentEvent = 'message';
  let dataLines = [];

  const flush = (at) => {
    if (dataLines.length === 0) return;
    events.push({ event: currentEvent, data: dataLines.join('\n'), at });
    currentEvent = 'message';
    dataLines = [];
  };

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    const at = Date.now();
    buffer += decoder.decode(value, { stream: true });

    let nl;
    while ((nl = buffer.indexOf('\n')) !== -1) {
      let line = buffer.slice(0, nl);
      buffer = buffer.slice(nl + 1);
      if (line.endsWith('\r')) line = line.slice(0, -1);

      if (line === '') {
        flush(at);
        continue;
      }
      if (line.startsWith(':')) continue; // comment / heartbeat
      if (line.startsWith('event:')) {
        currentEvent = line.slice(6).trim();
        continue;
      }
      if (line.startsWith('data:')) {
        dataLines.push(line.slice(5).trimStart());
      }
    }
  }
  flush(Date.now());

  return { events, headers: res.headers, status: res.status, started };
}

function analyzeProbe(events, intervalMs, count) {
  const ticks = events.filter((e) => e.event === 'tick');
  assert(ticks.length >= count, `probe expected >=${count} ticks, got ${ticks.length}`);

  const gaps = [];
  for (let i = 1; i < ticks.length; i++) {
    gaps.push(ticks[i].at - ticks[i - 1].at);
  }

  const span = ticks[ticks.length - 1].at - ticks[0].at;
  const expectedSpan = intervalMs * (ticks.length - 1);
  const meanGap = gaps.reduce((a, b) => a + b, 0) / gaps.length;
  const burst = span < expectedSpan * BURST_RATIO;

  const withinTolerance = gaps.every(
    (g) => Math.abs(g - intervalMs) <= Math.max(BUFFER_TOLERANCE_MS, intervalMs * 0.6)
  );

  return {
    tickCount: ticks.length,
    gaps,
    meanGap: Math.round(meanGap),
    span,
    expectedSpan,
    burst,
    withinTolerance,
    pass: !burst && withinTolerance,
  };
}

function analyzeCoach(events) {
  const tokens = events.filter((e) => e.event === 'token');
  const errors = events.filter((e) => e.event === 'error');
  const done = events.some((e) => e.event === 'done');

  assert(errors.length === 0, `coach stream error: ${errors[0]?.data}`);
  assert(tokens.length > 0, 'coach stream produced zero token events');
  assert(done, 'coach stream missing done event');

  const text = tokens
    .map((e) => {
      try {
        return JSON.parse(e.data).text ?? '';
      } catch {
        return e.data;
      }
    })
    .join('');

  assert(text.trim().length > 0, 'coach stream assembled empty answer');

  const firstTokenAt = tokens[0].at;
  const lastTokenAt = tokens[tokens.length - 1].at;
  const span = lastTokenAt - firstTokenAt;
  // Multiple token events that aren't all in one instant ⇒ progressive delivery.
  const progressive = tokens.length >= 2 && span >= 15;

  return {
    tokenEvents: tokens.length,
    chars: text.length,
    span,
    progressive,
    preview: text.slice(0, 120),
    pass: progressive || tokens.length === 1, // single tiny reply still OK
  };
}

async function main() {
  console.log(`SSE verify against ${BASE}`);
  console.log(`  probe interval=${INTERVAL_MS}ms count=${COUNT}`);

  // ── 1. Timed probe (no LLM) ──────────────────────────────────────────────
  const probe = await readSse(`/api/coach/sse-probe?intervalMs=${INTERVAL_MS}&count=${COUNT}`);
  const accel = probe.headers.get('x-accel-buffering');
  console.log(`  X-Accel-Buffering: ${accel ?? '(absent)'}`);

  const probeResult = analyzeProbe(probe.events, INTERVAL_MS, COUNT);
  console.log(
    `  probe ticks=${probeResult.tickCount} meanGap=${probeResult.meanGap}ms ` +
      `span=${probeResult.span}ms expected≈${probeResult.expectedSpan}ms ` +
      `gaps=[${probeResult.gaps.join(',')}]`
  );
  assert(
    probeResult.pass,
    probeResult.burst
      ? `SSE appears BUFFERED (ticks arrived in ${probeResult.span}ms burst; expected ~${probeResult.expectedSpan}ms)`
      : `SSE tick spacing out of tolerance (mean ${probeResult.meanGap}ms, expected ${INTERVAL_MS}ms)`
  );
  console.log('✓ sse-probe delivers unbuffered timed ticks');

  if (SKIP_COACH) {
    console.log('SKIP_COACH=1 — skipping Groq coach stream check.');
    console.log('All requested SSE checks passed.');
    return;
  }

  // ── 2. Coach stream via Groq ─────────────────────────────────────────────
  const coach = await readSse('/api/coach/stream', {
    method: 'POST',
    body: {
      userId: 'sse-verify-user',
      question: 'In two short sentences, what does consistency look like for someone just starting to log movement?',
      history: [],
    },
  });

  const coachResult = analyzeCoach(coach.events);
  console.log(
    `  coach tokens=${coachResult.tokenEvents} chars=${coachResult.chars} ` +
      `span=${coachResult.span}ms progressive=${coachResult.progressive}`
  );
  console.log(`  preview: ${coachResult.preview}…`);
  assert(coachResult.pass, 'coach stream did not deliver progressive tokens');
  console.log('✓ /api/coach/stream streams Groq tokens over SSE');

  console.log('All SSE checks passed.');
}

main().catch((err) => {
  console.error('SSE verify failed:', err.message);
  process.exit(1);
});

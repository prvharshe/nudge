/**
 * Minimal Server-Sent Events helpers for Express.
 * Cloud Run / proxies: disable buffering so tokens flush immediately.
 */

export function initSse(res) {
  res.status(200);
  res.setHeader('Content-Type', 'text/event-stream; charset=utf-8');
  res.setHeader('Cache-Control', 'no-cache, no-transform');
  res.setHeader('Connection', 'keep-alive');
  // Nginx / Cloud Run / CDN: do not buffer the body.
  res.setHeader('X-Accel-Buffering', 'no');
  // Disable Express/compression-style buffering where supported.
  if (typeof res.flushHeaders === 'function') {
    res.flushHeaders();
  }
  // Kick the stream so clients see headers + first bytes immediately.
  res.write(': connected\n\n');
}

export function sendSse(res, event, data) {
  const payload = typeof data === 'string' ? data : JSON.stringify(data);
  if (event) {
    res.write(`event: ${event}\n`);
  }
  // Split multi-line payloads per SSE spec.
  for (const line of String(payload).split('\n')) {
    res.write(`data: ${line}\n`);
  }
  res.write('\n');
}

export function endSse(res) {
  sendSse(res, 'done', '[DONE]');
  res.end();
}

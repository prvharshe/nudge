#!/usr/bin/env node
/**
 * Focused checks for the Groq chat-model migration (no live API calls).
 */
import assert from 'node:assert/strict';
import {
  DEFAULT_GROQ_CHAT_MODEL,
  GROQ_CHAT_MODEL,
  buildGroqChatParams,
} from '../services/groq.js';

assert.equal(DEFAULT_GROQ_CHAT_MODEL, 'openai/gpt-oss-20b');
assert.equal(GROQ_CHAT_MODEL, process.env.GROQ_CHAT_MODEL || 'openai/gpt-oss-20b');
assert.doesNotMatch(GROQ_CHAT_MODEL, /llama-3\.1-8b-instant/);

const shortCall = buildGroqChatParams({
  messages: [{ role: 'user', content: 'hi' }],
  max_tokens: 60,
  temperature: 0.85,
});

assert.equal(shortCall.model, GROQ_CHAT_MODEL);
assert.equal(shortCall.reasoning_effort, 'low');
assert.equal(shortCall.reasoning_format, 'hidden');
assert.equal(shortCall.max_tokens, 512, 'short max_tokens must be floored for GPT-OSS reasoning headroom');
assert.equal(shortCall.temperature, 0.85);

const coachCall = buildGroqChatParams({
  messages: [{ role: 'user', content: 'hi' }],
  max_tokens: 2048,
  temperature: 0.75,
});
assert.equal(coachCall.max_tokens, 2048, 'larger caps should be preserved');

const override = buildGroqChatParams({
  model: 'custom/model',
  messages: [],
  max_tokens: 200,
});
assert.equal(override.model, 'custom/model');

console.log('✓ Groq chat model defaults and GPT-OSS param compatibility checks passed');

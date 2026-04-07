import Groq from 'groq-sdk';

let _client = null;
function client() {
  if (!_client) _client = new Groq({ apiKey: process.env.GROQ_API_KEY });
  return _client;
}

const NUDGE_SYSTEM_PROMPT = `You are a warm, encouraging personal movement coach.
Your job is to write exactly 2 sentences as a morning nudge message.
Rules:
- Each entry includes a date — use those dates to understand what is recent vs old. The most recent entry is the most important.
- ONLY reference things that are explicitly stated in the entries. Never invent or assume activities or outcomes.
- If the most recent entry says "did not move", acknowledge that honestly and gently — do not imply they moved
- Never use generic filler phrases like "keep it up", "great job", or "you've got this"
- Zero guilt or pressure — this is purely supportive
- Conversational tone, like a thoughtful friend who knows them well
- Reference specific patterns you see across multiple entries (streaks, favourite activities, recurring notes)
- End on a gentle, forward-looking note for today
- RECOVERY SIGNAL: If a recovery signal is provided, use the readiness score as your primary tone guide:
  • Score 0–34 (Tired) or 35–49 (Fair): body is under stress — soften the nudge significantly, celebrate rest, suggest something gentle. Never push hard.
  • Score 50–64 (Good): balanced tone, acknowledge they're recovering well.
  • Score 65–79 (Ready): can be mildly energising, encourage movement if they feel up to it.
  • Score 80–100 (Peak): be genuinely upbeat and energising — this is a great day to move.
  If no score is given, fall back to HR/HRV signals if present.`;

const COACH_SYSTEM_PROMPT = `You are a knowledgeable, warm personal movement coach with access to this person's complete movement history.
Rules:
- Answer directly and specifically, referencing their actual data wherever relevant
- Be conversational and insightful — like a thoughtful friend who genuinely knows their patterns
- Keep answers to 3–5 sentences, concise but meaningful
- If you spot a real pattern (specific days, activity types, streaks, gaps), name it explicitly
- If there's not enough history to answer well, say so honestly and tell them what to log
- Never be preachy or lecture about health — focus on patterns, observations, and encouragement
- Never use filler phrases like "great job" or "keep it up"
- IMPORTANT: If the person sends a short acknowledgment like "thanks", "ok", "alright", "got it", "cool", or similar closing remarks — do NOT repeat or summarise what was already discussed. Instead, respond with a single genuinely motivating sentence that highlights one concrete positive thing you can see in their data (a streak, a favourite activity, a recent win). Keep it fresh, specific, and forward-looking.`;

/**
 * Parse a date from an entry string like "On Wed Mar 12 2025, the user..."
 * Returns a Date object, or epoch if parsing fails.
 */
function parseDateFromEntry(entry) {
  const match = entry.match(/^On (.+?),/);
  if (!match) return new Date(0);
  const d = new Date(match[1]);
  return isNaN(d.getTime()) ? new Date(0) : d;
}

/**
 * Sort entries newest-first by the date embedded in their content.
 */
function sortEntriesByDate(entries) {
  return [...entries].sort((a, b) => parseDateFromEntry(b) - parseDateFromEntry(a));
}

/**
 * Build a goal context line to inject into prompts.
 * Returns empty string if no goal.
 */
function goalLine(goal) {
  return goal ? `\nThis person's primary fitness goal is to ${goalLabel(goal)}.` : '';
}

function goalLabel(goal) {
  const labels = {
    lose_weight: 'lose weight and burn fat',
    build_muscle: 'build muscle and get stronger',
    improve_endurance: 'improve endurance and cardiovascular fitness',
    stay_active: 'stay consistently active and build a movement habit',
    feel_better: 'feel better overall — more energy, less stress',
  };
  return labels[goal] || goal.replace(/_/g, ' ');
}

/**
 * Generate a personalised 2-sentence morning nudge.
 * @param {string[]} entries  Entries from Supermemory (any order)
 * @param {string}   userName The user's first name (default: 'friend')
 * @returns {string}          The 2-sentence nudge message
 */
export async function generateNudge(entries, userName = 'friend', recoveryContext = null, goal = null, profileSummary = null) {
  if (entries.length === 0) {
    return `Today is a great day to start tracking your movement, ${userName} — even a short walk counts. Check in tonight and I'll have something personal for you tomorrow morning.`;
  }

  // Sort by the date embedded in the entry text so Groq sees true chronological order
  const sorted = sortEntriesByDate(entries).slice(0, 14);

  const today = new Date().toDateString(); // e.g. "Thu Mar 13 2025"
  const context = sorted.map((e, i) => `Entry ${i + 1}: ${e}`).join('\n');

  const recoveryLine = recoveryContext
    ? `\nToday's recovery signal (from Apple Health): ${recoveryContext}`
    : '';
  const goalContext = goalLine(goal);
  const profileLine = profileSummary ? `\n${profileSummary}` : '';

  const userPrompt = `Today's date: ${today}${recoveryLine}${goalContext}${profileLine}\n\nYou are writing for someone named ${userName}. Here are their recent movement entries, sorted newest first:\n\n${context}\n\nWrite their 2-sentence morning nudge for today. You may naturally use their name (${userName}) once if it feels right.`;

  const completion = await client().chat.completions.create({
    model: 'llama-3.1-8b-instant',
    messages: [
      { role: 'system', content: NUDGE_SYSTEM_PROMPT },
      { role: 'user', content: userPrompt },
    ],
    max_tokens: 120,
    temperature: 0.8,
  });

  const message = completion.choices[0]?.message?.content?.trim();
  if (!message) throw new Error('Groq returned empty message');
  return message;
}

/**
 * Answer a free-form question from the user using their movement history as context.
 * @param {string[]} entries  Relevant entries from Supermemory (semantic search results)
 * @param {string}   question The user's question
 * @param {Array<{role: string, content: string}>} history  Recent conversation turns (oldest first)
 * @returns {string}          The coach's answer
 */
export async function generateCoachAnswer(entries, question, history = [], goal = null, profileSummary = null, profileMems = []) {
  const entriesText = entries.length > 0
    ? entries.map((e, i) => `Entry ${i + 1}: ${e}`).join('\n')
    : 'No movement history stored yet.';

  const profileLine = profileSummary ? `\n${profileSummary}` : '';

  let systemWithContext = `${COACH_SYSTEM_PROMPT}${goalLine(goal)}${profileLine}\n\nMovement history and context (most relevant to the question):\n${entriesText}`;

  if (profileMems.length > 0) {
    systemWithContext += `\n\nPersistent user profile (from memory):\n${profileMems.join('\n')}`;
  }

  const messages = [
    { role: 'system', content: systemWithContext },
    ...history,
    { role: 'user', content: question },
  ];

  const completion = await client().chat.completions.create({
    model: 'llama-3.1-8b-instant',
    messages,
    max_tokens: 200,
    temperature: 0.75,
  });

  const message = completion.choices[0]?.message?.content?.trim();
  if (!message) throw new Error('Groq returned empty coach answer');
  return message;
}

const REACTION_SYSTEM_PROMPT = `You are a personal movement coach reacting to a just-logged entry.
Write EXACTLY ONE sentence (under 18 words) that:
- References something specific from the person's recent history (a streak, a repeated pattern, a previous activity)
- Feels like a genuine observation from someone who knows their data — not a compliment
- Has no filler phrases like "great job", "well done", or "keep it up"
- If there's no history yet, write a warm single sentence welcoming them to the start of their journey`;

const WEEKLY_SYSTEM_PROMPT = `You are a personal movement coach giving a weekly pattern analysis.
Write exactly 3 sentences:
1. Consistency summary — use real numbers from the data (e.g. "X of the last Y days")
2. Strongest pattern — name the specific day, activity type, or streak you see in the data
3. One forward-looking observation for the coming week that feels personally relevant
Rules:
- Reference actual data points, not vague generalities
- Conversational, warm tone — like a coach who genuinely reviewed the data
- No filler phrases, no generic health advice`;

/**
 * Generate a one-sentence reaction to a just-logged entry.
 * @param {string[]} entries  Recent entries for context
 * @param {boolean}  didMove  Whether the user moved today
 * @param {string[]} activities  Activity tags logged (e.g. ["walk","run"])
 * @returns {string}  One-sentence reaction
 */
export async function generateReaction(entries, didMove, activities, goal = null, profileSummary = null) {
  const context = entries.length > 0
    ? entries.map((e, i) => `Entry ${i + 1}: ${e}`).join('\n')
    : 'No prior history yet.';

  const todayDesc = didMove
    ? `They just logged movement today${activities.length ? ` (${activities.join(', ')})` : ''}.`
    : "They just logged a rest day today.";

  const goalCtx    = goal          ? `\nThis person's goal: ${goalLabel(goal)}.`  : '';
  const profileCtx = profileSummary ? `\n${profileSummary}` : '';
  const userPrompt = `Recent history:\n${context}\n\n${todayDesc}${goalCtx}${profileCtx}\n\nWrite your one-sentence reaction.`;

  const completion = await client().chat.completions.create({
    model: 'llama-3.1-8b-instant',
    messages: [
      { role: 'system', content: REACTION_SYSTEM_PROMPT },
      { role: 'user', content: userPrompt },
    ],
    max_tokens: 60,
    temperature: 0.85,
  });

  const message = completion.choices[0]?.message?.content?.trim();
  if (!message) throw new Error('Groq returned empty reaction');
  return message;
}

/**
 * Generate a 3-sentence weekly pattern insight.
 * @param {string[]} entries  Up to 30 recent entries
 * @returns {string}  The weekly insight text
 */
export async function generateWeeklyInsight(entries, goal = null, profileSummary = null) {
  if (entries.length === 0) {
    return "You haven't logged any entries yet — start checking in each evening and I'll have a real pattern analysis for you next week.";
  }

  const context = entries.map((e, i) => `Entry ${i + 1}: ${e}`).join('\n');
  const goalCtx    = goal           ? `\nThis person's fitness goal: ${goalLabel(goal)}.` : '';
  const profileCtx = profileSummary ? `\n${profileSummary}` : '';
  const userPrompt = `Here are this person's recent movement entries (newest first):\n\n${context}${goalCtx}${profileCtx}\n\nWrite their 3-sentence weekly pattern analysis.`;

  const completion = await client().chat.completions.create({
    model: 'llama-3.1-8b-instant',
    messages: [
      { role: 'system', content: WEEKLY_SYSTEM_PROMPT },
      { role: 'user', content: userPrompt },
    ],
    max_tokens: 160,
    temperature: 0.75,
  });

  const message = completion.choices[0]?.message?.content?.trim();
  if (!message) throw new Error('Groq returned empty weekly insight');
  return message;
}

/**
 * Summarise a coach conversation into 2-3 sentences for Supermemory storage.
 * @param {Array<{role: string, content: string}>} messages
 * @returns {string|null}
 */
export async function summarizeConversation(messages) {
  if (!messages?.length) return null;
  const transcript = messages
    .map(m => `${m.role === 'user' ? 'User' : 'Coach'}: ${m.content}`)
    .join('\n');

  const completion = await client().chat.completions.create({
    model: 'llama-3.1-8b-instant',
    messages: [
      {
        role: 'system',
        content: 'Summarise this coaching conversation in 2-3 sentences. Focus on: what the user asked about, patterns or insights identified, and any goals or intentions the user mentioned. Be specific with activities, numbers, and dates where present. Use past tense. Start with "Coaching session:"'
      },
      { role: 'user', content: transcript }
    ],
    max_tokens: 120,
    temperature: 0.3,
  });

  return completion.choices[0]?.message?.content?.trim() ?? null;
}

// ── Learn insight ─────────────────────────────────────────────────────────────

const LEARN_SYSTEM_PROMPT = `You are a health science educator for a fitness tracking app called Nudge.
Write ONE educational health insight (3-4 sentences) that:
- Directly connects to the user's actual metrics provided
- Explains the biological or physiological science behind what their numbers mean
- Is grounded ONLY in established scientific consensus (NIH, WHO, AHA, peer-reviewed meta-analyses)
- Ends with one specific, actionable takeaway relevant to today

Rules:
- Focus on ONE metric or pattern — the most interesting or actionable given the data
- Never speculate or cite unproven/controversial claims
- Use phrases like "research shows" or "studies suggest", never frame as medical advice
- Plain, warm, conversational tone — 3-4 sentences maximum, no lists, no headers
- Do not repeat the metric value robotically; weave it in naturally`;

/**
 * Generate a personalised educational health insight based on today's metrics.
 * @param {object} metrics — { restingHR, hrv, sleepHours, steps, recoveryScore, recoveryLabel, goal }
 * @param {string|null} profileSummary
 * @returns {string}
 */
export async function generateLearnInsight(metrics = {}, profileSummary = null) {
  const { restingHR, hrv, sleepHours, steps, recoveryScore, recoveryLabel, goal } = metrics;
  const parts = [];
  if (recoveryScore != null) parts.push(`Recovery score: ${recoveryScore}/100 (${recoveryLabel ?? ''})`);
  if (restingHR    != null) parts.push(`Resting heart rate: ${restingHR} BPM`);
  if (hrv          != null) parts.push(`HRV: ${hrv}ms`);
  if (sleepHours   != null) parts.push(`Sleep last night: ${Number(sleepHours).toFixed(1)} hours`);
  if (steps        != null) parts.push(`Steps today: ${Number(steps).toLocaleString()}`);
  if (goal)                 parts.push(`User goal: ${goal.replace(/_/g, ' ')}`);
  if (profileSummary)       parts.push(profileSummary);

  const userPrompt = parts.length > 0
    ? `Today's data:\n${parts.join('\n')}\n\nWrite today's health insight.`
    : 'Write a general health insight about movement, recovery, or nutrition.';

  const completion = await client().chat.completions.create({
    model: 'llama-3.1-8b-instant',
    messages: [
      { role: 'system', content: LEARN_SYSTEM_PROMPT },
      { role: 'user', content: userPrompt },
    ],
    max_tokens: 200,
    temperature: 0.7,
  });

  const message = completion.choices[0]?.message?.content?.trim();
  if (!message) throw new Error('Groq returned empty learn insight');
  return message;
}

// ── Health Report: Biomarker Extraction ──────────────────────────────────────

/**
 * Parse raw report text into structured biomarker JSON.
 * Returns an object like: { vitamin_d: { value: 18, unit: 'ng/mL', status: 'low', name: 'Vitamin D' }, ... }
 * @param {string} reportText
 * @returns {object}
 */
export async function extractBiomarkers(reportText) {
  const completion = await client().chat.completions.create({
    model: 'llama-3.1-8b-instant',
    messages: [
      {
        role: 'system',
        content: `You are a medical data parser. Extract all lab test results from the text.
Return ONLY valid JSON — an object where each key is a snake_case biomarker name.
Each value must have: { "name": string, "value": number|string, "unit": string, "status": "normal"|"low"|"high"|"borderline"|"unknown", "reference": string }
If a field is not present, omit it. Do not include any explanation or markdown — only the JSON object.`,
      },
      {
        role: 'user',
        content: `Extract all biomarkers from this health report:\n\n${reportText.slice(0, 6000)}`,
      },
    ],
    max_tokens: 1000,
    temperature: 0.1,
  });

  const raw = completion.choices[0]?.message?.content?.trim() ?? '{}';
  // Strip markdown code fences if present
  const cleaned = raw.replace(/^```json\s*/i, '').replace(/```$/i, '').trim();
  try {
    return JSON.parse(cleaned);
  } catch {
    return {};
  }
}

// ── Health Report: Insight Generation ────────────────────────────────────────

const REPORT_INSIGHT_SYSTEM_PROMPT = `You are a health educator for a fitness tracking app.
The user has uploaded a blood or health report. You have their lab results AND their fitness data (steps, sleep, HRV, recovery).

Write exactly 5-7 bullet point insights. Each bullet must:
- Start with a bold **Marker Name** or **Pattern** label
- Connect the lab finding directly to the user's fitness/movement data where possible
- Explain the science in 1-2 plain sentences (NIH/WHO/AHA level evidence only)
- End with ONE specific, actionable suggestion for today or this week

Format as a plain list — one bullet per line, starting with "•". No headers, no markdown beyond the bold labels, no medical advice framing. Use "research suggests" or "studies show" rather than definitive claims.`;

/**
 * Generate personalised bullet-point insights from biomarkers + health context.
 * @param {object} biomarkers — structured output from extractBiomarkers()
 * @param {object} hkMetrics — { steps, sleepHours, restingHR, hrv, recoveryScore, recoveryLabel }
 * @param {string[]} memories — recent Supermemory entries for context
 * @param {string|null} profileSummary
 * @returns {string[]} — array of bullet strings (without the leading "•")
 */
export async function generateReportInsights(biomarkers = {}, hkMetrics = {}, memories = [], profileSummary = null) {
  const bioLines = Object.values(biomarkers).map(b =>
    `${b.name}: ${b.value}${b.unit ? ' ' + b.unit : ''} — ${b.status}${b.reference ? ` (ref: ${b.reference})` : ''}`
  ).join('\n');

  const hkLines = [];
  if (hkMetrics.recoveryScore != null) hkLines.push(`Recovery score: ${hkMetrics.recoveryScore}/100 (${hkMetrics.recoveryLabel ?? ''})`);
  if (hkMetrics.restingHR != null)     hkLines.push(`Resting HR: ${hkMetrics.restingHR} BPM`);
  if (hkMetrics.hrv != null)           hkLines.push(`HRV: ${hkMetrics.hrv}ms`);
  if (hkMetrics.sleepHours != null)    hkLines.push(`Sleep: ${Number(hkMetrics.sleepHours).toFixed(1)} hrs`);
  if (hkMetrics.steps != null)         hkLines.push(`Steps today: ${Number(hkMetrics.steps).toLocaleString()}`);

  const memSection = memories.length > 0
    ? `\nRecent activity history:\n${memories.slice(0, 5).join('\n')}`
    : '';
  const profileSection = profileSummary ? `\nUser profile: ${profileSummary}` : '';

  const userPrompt = `Lab results:\n${bioLines || 'No structured biomarkers found — provide general wellness insights.'}\n\nFitness data:\n${hkLines.join('\n') || 'No fitness data available.'}${memSection}${profileSection}\n\nWrite 5-7 personalised insights.`;

  const completion = await client().chat.completions.create({
    model: 'llama-3.1-8b-instant',
    messages: [
      { role: 'system', content: REPORT_INSIGHT_SYSTEM_PROMPT },
      { role: 'user', content: userPrompt },
    ],
    max_tokens: 600,
    temperature: 0.65,
  });

  const text = completion.choices[0]?.message?.content?.trim() ?? '';
  // Split on bullet markers and clean up
  return text
    .split('\n')
    .filter(l => l.trim().startsWith('•'))
    .map(l => l.replace(/^•\s*/, '').trim())
    .filter(Boolean);
}

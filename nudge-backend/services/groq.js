import Groq from 'groq-sdk';

let _client = null;
function client() {
  if (!_client) _client = new Groq({ apiKey: process.env.GROQ_API_KEY });
  return _client;
}

const NUDGE_SYSTEM_PROMPT = `You are a warm, encouraging personal movement coach.
Your job is to write exactly 2 sentences as a morning nudge message.
Rules:
- You MUST reference specific details from the user's recent history (specific activities, notes, or patterns you see)
- Never use generic filler phrases like "keep it up", "great job", or "you've got this"
- Zero guilt or pressure — this is purely supportive
- Conversational tone, like a thoughtful friend who knows them well
- If you see patterns (e.g., moves on weekdays, walks often, mentions work stress), reference them
- End on a gentle, forward-looking note for today`;

const COACH_SYSTEM_PROMPT = `You are a knowledgeable, warm personal movement coach with access to this person's complete movement history.
Rules:
- Answer directly and specifically, referencing their actual data wherever relevant
- Be conversational and insightful — like a thoughtful friend who genuinely knows their patterns
- Keep answers to 3–5 sentences, concise but meaningful
- If you spot a real pattern (specific days, activity types, streaks, gaps), name it explicitly
- If there's not enough history to answer well, say so honestly and tell them what to log
- Never be preachy or lecture about health — focus on patterns, observations, and encouragement
- Never use filler phrases like "great job" or "keep it up"`;

/**
 * Generate a personalised 2-sentence morning nudge.
 * @param {string[]} entries  Recent entries as strings, newest first
 * @returns {string}          The 2-sentence nudge message
 */
export async function generateNudge(entries) {
  if (entries.length === 0) {
    return "Today is a great day to start tracking your movement — even a short walk counts. Check in tonight and I'll have something personal for you tomorrow morning.";
  }

  const context = entries
    .slice(0, 14)
    .map((e, i) => `Entry ${i + 1}: ${e}`)
    .join('\n');

  const userPrompt = `Here are this person's recent movement entries (newest first):\n\n${context}\n\nWrite their 2-sentence morning nudge for today.`;

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
 * @returns {string}          The coach's answer
 */
export async function generateCoachAnswer(entries, question) {
  const context = entries.length > 0
    ? entries.map((e, i) => `Entry ${i + 1}: ${e}`).join('\n')
    : 'No movement history stored yet.';

  const userPrompt = `Here is this person's relevant movement history (most relevant entries first):\n\n${context}\n\nTheir question: ${question}`;

  const completion = await client().chat.completions.create({
    model: 'llama-3.1-8b-instant',
    messages: [
      { role: 'system', content: COACH_SYSTEM_PROMPT },
      { role: 'user', content: userPrompt },
    ],
    max_tokens: 200,
    temperature: 0.75,
  });

  const message = completion.choices[0]?.message?.content?.trim();
  if (!message) throw new Error('Groq returned empty coach answer');
  return message;
}

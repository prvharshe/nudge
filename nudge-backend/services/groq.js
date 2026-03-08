import Groq from 'groq-sdk';

let _client = null;
function client() {
  if (!_client) _client = new Groq({ apiKey: process.env.GROQ_API_KEY });
  return _client;
}

const SYSTEM_PROMPT = `You are a warm, encouraging personal movement coach.
Your job is to write exactly 2 sentences as a morning nudge message.
Rules:
- You MUST reference specific details from the user's recent history (specific activities, notes, or patterns you see)
- Never use generic filler phrases like "keep it up", "great job", or "you've got this"
- Zero guilt or pressure — this is purely supportive
- Conversational tone, like a thoughtful friend who knows them well
- If you see patterns (e.g., moves on weekdays, walks often, mentions work stress), reference them
- End on a gentle, forward-looking note for today`;

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
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: userPrompt },
    ],
    max_tokens: 120,
    temperature: 0.8,
  });

  const message = completion.choices[0]?.message?.content?.trim();
  if (!message) throw new Error('Groq returned empty message');
  return message;
}

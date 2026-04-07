import pdfParse from 'pdf-parse/lib/pdf-parse.js';
import { client } from './groq.js';

/**
 * Extract raw text from a PDF buffer.
 * @param {Buffer} buffer
 * @returns {string}
 */
async function extractPdfText(buffer) {
  const result = await pdfParse(buffer);
  return result.text?.trim() ?? '';
}

/**
 * Extract text from an image buffer via Groq vision (llama-4 scout).
 * @param {Buffer} buffer
 * @param {string} mimeType e.g. 'image/jpeg'
 * @returns {string}
 */
async function extractImageText(buffer, mimeType) {
  const base64 = buffer.toString('base64');
  const dataUrl = `data:${mimeType};base64,${base64}`;

  const completion = await client().chat.completions.create({
    model: 'meta-llama/llama-4-scout-17b-16e-instruct',
    messages: [
      {
        role: 'user',
        content: [
          {
            type: 'image_url',
            image_url: { url: dataUrl },
          },
          {
            type: 'text',
            text: 'This is a medical health report. Extract ALL text from this image exactly as it appears, preserving the structure (test names, values, units, reference ranges, flags). Return only the raw extracted text — no commentary.',
          },
        ],
      },
    ],
    max_tokens: 2000,
  });

  return completion.choices[0]?.message?.content?.trim() ?? '';
}

/**
 * Extract text from a report file (PDF or image).
 * @param {Buffer} buffer
 * @param {string} mimeType
 * @returns {string}
 */
export async function extractReportText(buffer, mimeType) {
  if (mimeType === 'application/pdf') {
    return extractPdfText(buffer);
  }
  if (mimeType.startsWith('image/')) {
    return extractImageText(buffer, mimeType);
  }
  throw new Error(`Unsupported file type: ${mimeType}`);
}

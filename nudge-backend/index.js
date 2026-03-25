import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import entriesRouter from './routes/entries.js';
import nudgeRouter from './routes/nudge.js';
import coachRouter from './routes/coach.js';
import reactionRouter from './routes/reaction.js';
import weeklyRouter from './routes/weekly.js';
import memoriesRouter from './routes/memories.js';
import learnRouter from './routes/learn.js';

const app = express();
const PORT = process.env.PORT ?? 3000;

// Middleware
app.use(cors());
app.use(express.json());

// Routes
app.use('/api/entries', entriesRouter);
app.use('/api/nudge', nudgeRouter);
app.use('/api/coach', coachRouter);
app.use('/api/reaction', reactionRouter);
app.use('/api/weekly', weeklyRouter);
app.use('/api/memories', memoriesRouter);
app.use('/api/learn', learnRouter);

// Health check
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.listen(PORT, () => {
  console.log(`Nudge backend running on http://localhost:${PORT}`);
  console.log(`  POST /api/entries   — log movement`);
  console.log(`  GET  /api/nudge     — get morning nudge`);
  console.log(`  POST /api/coach     — ask your coach`);
  console.log(`  POST /api/reaction  — post-log reaction`);
  console.log(`  POST /api/weekly    — weekly pattern insight`);
  console.log(`  POST /api/memories  — store typed memory`);
  console.log(`  POST /api/memories/summarize-convo — store conversation summary`);
  console.log(`  POST /api/learn     — daily educational health insight`);
  console.log(`  GET  /api/health    — health check`);
});

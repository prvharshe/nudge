import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import entriesRouter from './routes/entries.js';
import nudgeRouter from './routes/nudge.js';

const app = express();
const PORT = process.env.PORT ?? 3000;

// Middleware
app.use(cors());
app.use(express.json());

// Routes
app.use('/api/entries', entriesRouter);
app.use('/api/nudge', nudgeRouter);

// Health check
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.listen(PORT, () => {
  console.log(`Nudge backend running on http://localhost:${PORT}`);
  console.log(`  POST /api/entries  — log movement`);
  console.log(`  GET  /api/nudge    — get morning nudge`);
  console.log(`  GET  /api/health   — health check`);
});

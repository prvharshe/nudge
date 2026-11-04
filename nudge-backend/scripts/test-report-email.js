#!/usr/bin/env node
/**
 * Unit checks for the report-card renderer (no API keys required).
 * Pass --out <dir> to also write week.html / month.html for eyeballing.
 */
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { grade, renderReportEmail, summarize, validateReport } from '../services/reportEmail.js';

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

const R = (name, detail, done) => ({ name, detail, done });
const ymd = (y, m, d) => `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;

// Week Mon Nov 2 – Sun Nov 8 2026. Evening Hair Ras missed on the weekend.
const steps = [5200, 3100, 8000, 4000, 12050, 2500, 6100];
const week = {
  kind: 'week', start: '2026-11-02', end: '2026-11-08', stepGoal: 4000,
  days: steps.map((s, i) => {
    const weekend = i >= 5;
    return {
      date: ymd(2026, 11, 2 + i), steps: s,
      routines: [R('Hair Ras', 'after breakfast', true), R('Hair Ras', 'after dinner', !weekend)],
    };
  }),
};

validateReport(week);
const ws = summarize(week);
assert(ws.routine.due === 14 && ws.routine.done === 12, `routine totals: ${JSON.stringify(ws.routine)}`);
assert(ws.routine.pct === 86 && ws.routine.grade === 'B', `routine pct/grade: ${ws.routine.pct} ${ws.routine.grade}`);
assert(ws.steps.hitDays === 5 && ws.steps.stepDays === 7, 'exactly 4000 counts as a hit; 3100 and 2500 miss');
assert(ws.steps.avg === Math.round(steps.reduce((a, b) => a + b) / 7), 'average steps');
assert(ws.steps.bestRun === 3, `best run Wed–Fri = 3, got ${ws.steps.bestRun}`);
assert(ws.routines.length === 2, 'morning and evening Hair Ras are separate slots');
assert(ws.routines[1].detail === 'after dinner' && ws.routines[1].done === 5, 'evening slot 5/7, sorted last');
assert(ws.insights.some(t => t.includes('after dinner')), 'most-missed insight names the evening slot');
assert(ws.insights.some(t => t.includes('weekends 50% vs weekdays 100%')), `weekend insight: ${ws.insights}`);
assert(ws.weeks.length === 1 && ws.weeks[0].every(Boolean), 'Mon-start week fills one row');

assert(grade(90) === 'A' && grade(89) === 'B' && grade(59) === 'F' && grade(null) === '–', 'grade bands');

// Month: October 2026 starts on a Thursday; first days untracked (before Routines shipped).
const month = {
  kind: 'month', start: '2026-10-01', end: '2026-10-31',
  days: Array.from({ length: 31 }, (_, i) => ({
    date: ymd(2026, 10, i + 1),
    steps: i === 10 ? null : 3000 + i * 200,
    routines: i < 3 ? null : [R('Biotin <b>', '', i % 4 !== 0)],
  })),
};
validateReport(month);
const ms = summarize(month);
assert(ms.weeks.length === 5, `Oct 2026 spans 5 Mon-start weeks, got ${ms.weeks.length}`);
assert(ms.weeks[0][3]?.date === '2026-10-01' && ms.weeks[0][2] === null, 'Oct 1 lands on Thursday column');
assert(ms.days.slice(0, 3).every(d => !d.tracked && d.pct === null), 'untracked days are not counted as misses');
assert(ms.routine.due === 28, 'only tracked days count toward due');
assert(ms.steps.stepDays === 30, 'missing step day excluded');
assert(ms.weekRows.length === 5 && ms.weekRows[0].start === '2026-10-01', 'week rows');

const { html: mHtml, subject: mSubject } = renderReportEmail(month);
assert(!mHtml.includes('Biotin <b>') && mHtml.includes('Biotin &lt;b&gt;'), 'routine names are HTML-escaped');
assert(mSubject.startsWith('Nudge October report card'), `month subject: ${mSubject}`);
const { html: wHtml, subject: wSubject } = renderReportEmail(week);
assert(wSubject.includes('routines 86%') && wSubject.includes('steps 5/7'), `week subject: ${wSubject}`);
assert(!/<svg|<script/i.test(wHtml + mHtml), 'email HTML has no SVG or script');

for (const bad of [{}, { ...week, kind: 'year' }, { ...week, days: [] }, { ...week, days: [{ date: 'x' }] },
  { ...week, days: Array(32).fill(week.days[0]) },
  { ...week, days: [{ date: '2026-11-02', routines: [null] }] },
  { ...week, days: [{ date: '2026-11-02', routines: [{ name: 5, done: true }] }] },
  { ...week, stepGoal: 'x' }]) {
  let threw = false;
  try { validateReport(bad); } catch { threw = true; }
  assert(threw, `should reject ${JSON.stringify(bad).slice(0, 60)}`);
}

const outIdx = process.argv.indexOf('--out');
if (outIdx > 0) {
  const dir = process.argv[outIdx + 1];
  writeFileSync(join(dir, 'week.html'), wHtml);
  writeFileSync(join(dir, 'month.html'), mHtml);
  console.log(`wrote ${dir}/week.html and month.html`);
}
console.log('report-email: all checks passed');

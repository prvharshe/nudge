/**
 * Weekly / monthly habit report card → email-safe HTML.
 * Email clients strip SVG and JS, so every chart is a table with inline styles.
 *
 * Report shape (built on the phone, where routine ticks and steps live):
 * { kind: 'week'|'month', start: 'YYYY-MM-DD', end: 'YYYY-MM-DD', stepGoal: 4000,
 *   days: [{ date: 'YYYY-MM-DD', steps: number|null,
 *            routines: [{ name, detail, done }] | null }] }   // null = not tracked yet
 */

const C = {
  page: '#F3F4F6', card: '#FFFFFF', ink: '#111827', ink2: '#4B5563', ink3: '#6B7280',
  rule: '#E5E7EB', miss: '#D1D5DB', none: '#F3F4F6',
  // sequential green, light → dark (brand green #16A34A at the top)
  g1: '#BBF7D0', g2: '#4ADE80', g3: '#16A34A',
};

const FONT = "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif";

export function parseYmd(ymd) {
  const [y, m, d] = ymd.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}
const fmt = (ymd, opts) => parseYmd(ymd).toLocaleDateString('en-US', { timeZone: 'UTC', ...opts });

export function grade(pct) {
  if (pct == null) return '–';
  if (pct >= 90) return 'A';
  if (pct >= 80) return 'B';
  if (pct >= 70) return 'C';
  if (pct >= 60) return 'D';
  return 'F';
}

const pctOf = (done, due) => (due ? Math.round((done / due) * 100) : null);

/** Pure numbers for the report; everything the template shows comes from here. */
export function summarize(report) {
  const goal = report.stepGoal ?? 4000;
  const days = report.days.map(d => {
    const due = d.routines ? d.routines.length : 0;
    const done = d.routines ? d.routines.filter(r => r.done).length : 0;
    return {
      date: d.date,
      steps: d.steps,
      tracked: d.routines != null,
      due, done,
      pct: d.routines ? pctOf(done, due) : null,
      hit: d.steps != null && d.steps >= goal,
    };
  });

  const due = days.reduce((s, d) => s + d.due, 0);
  const done = days.reduce((s, d) => s + d.done, 0);
  const stepDays = days.filter(d => d.steps != null);
  const hitDays = stepDays.filter(d => d.hit).length;
  const avgSteps = stepDays.length
    ? Math.round(stepDays.reduce((s, d) => s + d.steps, 0) / stepDays.length) : null;

  // Per routine: name + detail identifies a slot (e.g. Hair Ras morning vs evening).
  const byRoutine = new Map();
  for (const d of report.days) {
    for (const r of d.routines ?? []) {
      const key = `${r.name}\u0000${r.detail ?? ''}`;
      const row = byRoutine.get(key) ?? { name: r.name, detail: r.detail ?? '', due: 0, done: 0 };
      row.due += 1;
      if (r.done) row.done += 1;
      byRoutine.set(key, row);
    }
  }
  const routines = [...byRoutine.values()]
    .map(r => ({ ...r, pct: pctOf(r.done, r.due) }))
    .sort((a, b) => b.pct - a.pct || a.name.localeCompare(b.name));

  // Longest run of consecutive step-goal days.
  let run = 0, bestRun = 0;
  for (const d of days) { run = d.hit ? run + 1 : 0; bestRun = Math.max(bestRun, run); }

  // Calendar weeks (Mon-start) for the monthly grid and week-by-week table.
  const weeks = [];
  for (const d of days) {
    const dow = (parseYmd(d.date).getUTCDay() + 6) % 7; // Mon=0
    if (!weeks.length || dow === 0) weeks.push(Array(7).fill(null));
    weeks[weeks.length - 1][dow] = d;
  }
  const weekRows = weeks.map(w => {
    const ds = w.filter(Boolean);
    const wDue = ds.reduce((s, d) => s + d.due, 0);
    const wDone = ds.reduce((s, d) => s + d.done, 0);
    const wStep = ds.filter(d => d.steps != null);
    return {
      start: ds[0].date, end: ds[ds.length - 1].date,
      routinePct: pctOf(wDone, wDue),
      hitDays: wStep.filter(d => d.hit).length, stepDays: wStep.length,
    };
  });

  const routinePct = pctOf(done, due);
  const stepPct = pctOf(hitDays, stepDays.length);
  return {
    kind: report.kind, start: report.start, end: report.end, goal,
    days, weeks, weekRows, routines,
    routine: { due, done, pct: routinePct, grade: grade(routinePct) },
    steps: { hitDays, stepDays: stepDays.length, avg: avgSteps, pct: stepPct, grade: grade(stepPct), bestRun },
    insights: insights(days, routines, goal),
  };
}

/** A few plain-English observations; deterministic so they never invent facts. */
function insights(days, routines, goal) {
  const out = [];
  const missed = routines.filter(r => r.done < r.due).sort((a, b) => a.pct - b.pct)[0];
  if (missed) out.push(`Most missed: <b>${esc(missed.name)}</b>${missed.detail ? ` (${esc(missed.detail)})` : ''}, done ${missed.done} of ${missed.due} times.`);
  else if (routines.length) out.push('Every routine was ticked off on every scheduled day. Perfect run.');

  const tracked = days.filter(d => d.tracked && d.due);
  const wk = tracked.filter(d => [0, 6].includes(parseYmd(d.date).getUTCDay()));
  const wd = tracked.filter(d => ![0, 6].includes(parseYmd(d.date).getUTCDay()));
  const p = ds => pctOf(ds.reduce((s, d) => s + d.done, 0), ds.reduce((s, d) => s + d.due, 0));
  if (wk.length && wd.length && Math.abs(p(wk) - p(wd)) >= 15) {
    out.push(`Routines: weekends ${p(wk)}% vs weekdays ${p(wd)}%.`);
  }

  const withSteps = days.filter(d => d.steps != null);
  if (withSteps.length) {
    const best = withSteps.reduce((a, b) => (b.steps > a.steps ? b : a));
    out.push(`Best step day: ${fmt(best.date, { weekday: 'long', month: 'short', day: 'numeric' })} with ${best.steps.toLocaleString('en-US')} steps.`);
    const low = withSteps.filter(d => d.steps < goal).length;
    if (low) out.push(`${low} day${low === 1 ? '' : 's'} under ${goal.toLocaleString('en-US')} steps.`);
  }
  return out;
}

// ─── Rendering ────────────────────────────────────────────────────────────────

export function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

const kSteps = n => (n >= 1000 ? `${(n / 1000).toFixed(n >= 10000 ? 0 : 1)}k` : String(n));

function routineFill(pct) {
  if (pct == null) return C.none;
  if (pct === 0) return C.miss;
  if (pct < 50) return C.g1;
  if (pct < 100) return C.g2;
  return C.g3;
}

function section(title, sub, body) {
  return `
  <tr><td style="padding:24px 24px 0 24px;">
    <div style="font:600 16px/1.3 ${FONT};color:${C.ink};">${title}</div>
    ${sub ? `<div style="font:13px/1.4 ${FONT};color:${C.ink3};padding-top:2px;">${sub}</div>` : ''}
    <div style="padding-top:14px;">${body}</div>
  </td></tr>`;
}

function tile(label, big, gradeLetter, line) {
  return `
  <td width="50%" valign="top" style="padding:0 6px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border:1px solid ${C.rule};border-radius:12px;">
      <tr><td style="padding:16px;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
          <td style="font:600 12px/1 ${FONT};color:${C.ink2};">${label}</td>
          <td align="right" style="font:700 22px/1 ${FONT};color:${C.ink};">${gradeLetter}</td>
        </tr></table>
        <div style="font:700 34px/1.1 ${FONT};color:${C.ink};padding-top:10px;">${big}</div>
        <div style="font:13px/1.4 ${FONT};color:${C.ink2};padding-top:4px;">${line}</div>
      </td></tr>
    </table>
  </td>`;
}

/** Vertical bar per day. heightPx 0..BAR_H; label above, day name below. */
const BAR_H = 96;
function barChart(cols) {
  const cells = cols.map(c => `
    <td align="center" valign="bottom" style="padding:0 3px;">
      <div style="font:600 11px/1 ${FONT};color:${C.ink2};padding-bottom:4px;">${c.top}</div>
      <div style="height:${BAR_H}px;line-height:0;font-size:0;" >
        <div style="height:${BAR_H - c.h}px;"></div>
        <div style="height:${c.h}px;background:${c.color};border-radius:4px 4px 0 0;"></div>
      </div>
      <div style="height:2px;background:${C.rule};"></div>
      <div style="font:11px/1 ${FONT};color:${C.ink3};padding-top:6px;">${c.label}</div>
    </td>`).join('');
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="table-layout:fixed;"><tr>${cells}</tr></table>`;
}

function hbar(pct) {
  const p = Math.max(0, Math.min(100, pct ?? 0));
  const filled = p ? `<td width="${p}%" style="background:${routineFill(pct)};height:8px;border-radius:4px;font-size:0;line-height:0;">&nbsp;</td>` : '';
  const rest = p < 100 ? `<td style="background:${C.none};height:8px;font-size:0;line-height:0;">&nbsp;</td>` : '';
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-radius:4px;"><tr>${filled}${rest}</tr></table>`;
}

function routineTable(routines) {
  if (!routines.length) return `<div style="font:13px ${FONT};color:${C.ink3};">No routines scheduled in this period.</div>`;
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0">` + routines.map(r => `
    <tr>
      <td width="45%" style="padding:8px 8px 8px 0;border-top:1px solid ${C.rule};">
        <div style="font:600 13px/1.3 ${FONT};color:${C.ink};">${esc(r.name)}</div>
        ${r.detail ? `<div style="font:12px/1.3 ${FONT};color:${C.ink3};">${esc(r.detail)}</div>` : ''}
      </td>
      <td style="padding:8px 0;border-top:1px solid ${C.rule};">${hbar(r.pct)}</td>
      <td width="56" align="right" style="padding:8px 0 8px 8px;border-top:1px solid ${C.rule};font:600 13px ${FONT};color:${C.ink};">${r.done}/${r.due}</td>
    </tr>`).join('') + `</table>`;
}

function legend(items) {
  return `<div style="font:11px/1.6 ${FONT};color:${C.ink3};padding-top:10px;">` + items.map(([color, text]) =>
    `<span style="display:inline-block;width:10px;height:10px;border-radius:3px;background:${color};vertical-align:-1px;"></span>&nbsp;${text}`
  ).join('&nbsp;&nbsp;&nbsp;') + `</div>`;
}

const STEP_LEGEND = goal => legend([[C.g3, `${goal.toLocaleString('en-US')}+ steps`], [C.miss, 'under goal']]);
const ROUTINE_LEGEND = legend([[C.g3, 'all done'], [C.g2, 'most'], [C.g1, 'some'], [C.miss, 'none'], [C.none, 'not tracked']]);

/** Month calendar: one cell per day, colored by `fillFor(day)`. */
function heatmap(weeks, fillFor, textFor) {
  const head = ['M', 'T', 'W', 'T', 'F', 'S', 'S'].map(d =>
    `<td align="center" style="font:600 11px ${FONT};color:${C.ink3};padding-bottom:4px;">${d}</td>`).join('');
  const rows = weeks.map(w => '<tr>' + w.map(d => {
    if (!d) return '<td style="padding:2px;"></td>';
    const bg = fillFor(d);
    const dark = bg === C.g3;
    return `<td style="padding:2px;"><div style="background:${bg};border-radius:6px;height:38px;text-align:center;">
      <div style="font:600 11px/1 ${FONT};color:${dark ? '#FFFFFF' : C.ink};padding-top:7px;">${Number(d.date.slice(8))}</div>
      <div style="font:10px/1 ${FONT};color:${dark ? '#FFFFFF' : C.ink2};padding-top:4px;">${textFor(d)}</div>
    </div></td>`;
  }).join('') + '</tr>').join('');
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="table-layout:fixed;"><tr>${head}</tr>${rows}</table>`;
}

function weekTable(rows) {
  const th = t => `<td style="font:600 11px ${FONT};color:${C.ink3};padding:6px 0;">${t}</td>`;
  const td = (t, a = 'left') => `<td align="${a}" style="font:13px ${FONT};color:${C.ink};padding:8px 0;border-top:1px solid ${C.rule};">${t}</td>`;
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0">
    <tr>${th('Week')}${th('Routines')}<td align="right" style="font:600 11px ${FONT};color:${C.ink3};">Step-goal days</td></tr>
    ${rows.map(r => `<tr>${td(`${fmt(r.start, { month: 'short', day: 'numeric' })} – ${fmt(r.end, { month: 'short', day: 'numeric' })}`)}${td(r.routinePct == null ? '–' : `${r.routinePct}% · ${grade(r.routinePct)}`)}${td(`${r.hitDays}/${r.stepDays}`, 'right')}</tr>`).join('')}
  </table>`;
}

export function renderReportEmail(report) {
  const s = summarize(report);
  const isWeek = s.kind === 'week';
  const range = `${fmt(s.start, { month: 'short', day: 'numeric' })} – ${fmt(s.end, { month: 'short', day: 'numeric', year: 'numeric' })}`;
  const title = isWeek ? 'Your week in habits' : `${fmt(s.start, { month: 'long', year: 'numeric' })} report card`;
  const subject = isWeek
    ? `Nudge weekly: routines ${s.routine.pct ?? '–'}%, steps ${s.steps.hitDays}/${s.steps.stepDays} days (${range})`
    : `Nudge ${fmt(s.start, { month: 'long' })} report card: routines ${s.routine.grade}, steps ${s.steps.grade}`;

  const tiles = `<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
    ${tile('ROUTINES', s.routine.pct == null ? '–' : `${s.routine.pct}%`, s.routine.grade, `${s.routine.done} of ${s.routine.due} ticked off`)}
    ${tile('STEPS', `${s.steps.hitDays}/${s.steps.stepDays}`, s.steps.grade,
      `days at ${s.goal.toLocaleString('en-US')}+${s.steps.avg != null ? ` · avg ${s.steps.avg.toLocaleString('en-US')}/day` : ''}`)}
  </tr></table>`;

  let charts;
  if (isWeek) {
    const maxSteps = Math.max(s.goal, ...s.days.map(d => d.steps ?? 0));
    const dayName = d => fmt(d.date, { weekday: 'short' });
    charts =
      section('Routines by day', 'Share of scheduled routines ticked off each day', barChart(s.days.map(d => ({
        top: d.tracked && d.due ? `${d.done}/${d.due}` : '–',
        h: d.pct == null ? 0 : Math.max(d.pct ? 4 : 0, Math.round((d.pct / 100) * BAR_H)),
        color: routineFill(d.pct), label: dayName(d),
      }))) + ROUTINE_LEGEND) +
      section('Steps by day', `Goal: ${s.goal.toLocaleString('en-US')} steps`, barChart(s.days.map(d => ({
        top: d.steps == null ? '–' : kSteps(d.steps),
        h: d.steps ? Math.max(4, Math.round((d.steps / maxSteps) * BAR_H)) : 0,
        color: d.hit ? C.g3 : C.miss, label: dayName(d),
      }))) + STEP_LEGEND(s.goal));
  } else {
    charts =
      section('Routines calendar', 'Each day colored by how many routines you ticked off',
        heatmap(s.weeks, d => routineFill(d.pct), d => (d.tracked && d.due ? `${d.done}/${d.due}` : '')) + ROUTINE_LEGEND) +
      section('Steps calendar', `Longest streak at ${s.goal.toLocaleString('en-US')}+: ${s.steps.bestRun} day${s.steps.bestRun === 1 ? '' : 's'}`,
        heatmap(s.weeks, d => (d.steps == null ? C.none : d.hit ? C.g3 : C.miss), d => (d.steps == null ? '' : kSteps(d.steps))) + STEP_LEGEND(s.goal)) +
      section('Week by week', '', weekTable(s.weekRows));
  }

  const notes = s.insights.length
    ? section('What stood out', '', `<ul style="margin:0;padding-left:18px;">${s.insights.map(i =>
        `<li style="font:14px/1.5 ${FONT};color:${C.ink};padding-bottom:4px;">${i}</li>`).join('')}</ul>`)
    : '';

  const html = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light"><title>${esc(title)}</title></head>
<body style="margin:0;padding:0;background:${C.page};">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${C.page};"><tr><td align="center" style="padding:24px 12px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;background:${C.card};border-radius:16px;">
    <tr><td style="padding:28px 24px 0 24px;">
      <div style="font:600 12px/1 ${FONT};color:${C.g3};">NUDGE</div>
      <div style="font:700 24px/1.25 ${FONT};color:${C.ink};padding-top:8px;">${esc(title)}</div>
      <div style="font:14px/1.4 ${FONT};color:${C.ink2};padding-top:4px;">${range}</div>
    </td></tr>
    <tr><td style="padding:20px 18px 0 18px;">${tiles}</td></tr>
    ${charts}
    ${section('By routine', 'Ticked off / scheduled', routineTable(s.routines))}
    ${notes}
    <tr><td style="padding:24px;font:12px/1.5 ${FONT};color:${C.ink3};">Grades: A 90%+, B 80%+, C 70%+, D 60%+. Steps grade is the share of days at your step goal.</td></tr>
  </table>
</td></tr></table>
</body></html>`;

  return { subject, html, summary: s };
}

/** Throws a message suitable for a 400 if the payload is malformed. */
export function validateReport(r) {
  const ymd = /^\d{4}-\d{2}-\d{2}$/;
  if (!r || !['week', 'month'].includes(r.kind)) throw new Error('kind must be week or month');
  if (!ymd.test(r.start ?? '') || !ymd.test(r.end ?? '')) throw new Error('start/end must be YYYY-MM-DD');
  if (r.stepGoal != null && !(Number.isFinite(r.stepGoal) && r.stepGoal > 0)) throw new Error('stepGoal must be a positive number');
  if (!Array.isArray(r.days) || r.days.length < 1 || r.days.length > 31) throw new Error('days must have 1–31 items');
  for (const d of r.days) {
    if (!ymd.test(d?.date ?? '')) throw new Error('day.date must be YYYY-MM-DD');
    if (d.steps != null && !Number.isFinite(d.steps)) throw new Error('day.steps must be a number');
    if (d.routines != null) {
      if (!Array.isArray(d.routines) || d.routines.length > 50) throw new Error('day.routines must be an array');
      for (const r of d.routines) {
        if (typeof r?.name !== 'string' || typeof r.done !== 'boolean' || (r.detail != null && typeof r.detail !== 'string')) {
          throw new Error('routine needs string name and boolean done');
        }
      }
    }
  }
}

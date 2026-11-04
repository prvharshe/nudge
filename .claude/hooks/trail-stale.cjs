#!/usr/bin/env node
// PreToolUse hook: when Claude reads or edits a file, flag trail learnings that mention that
// file but were written before later commits changed it. Fresh learnings print nothing.
// Usage as a hook: stdin is the hook JSON. Manual audit: `node trail-stale.cjs --all`.
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const git = (root, args) =>
  execFileSync('git', args, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();

function readLearnings(root) {
  const dir = path.join(root, '.trail', 'learnings');
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).filter(f => f.endsWith('.md')).map(f => {
    const text = fs.readFileSync(path.join(dir, f), 'utf8');
    const front = (text.match(/^---\n([\s\S]*?)\n---/) || [])[1] || '';
    const unquote = s => s.trim().replace(/^["']|["']$/g, '');
    const title = unquote((front.match(/^title:\s*(.+)$/m) || [])[1] || f);
    const block = (front.match(/^touches:\n((?:[ \t]+-.*\n?)*)/m) || [])[1] || '';
    const touches = block.split('\n').map(l => unquote(l.replace(/^\s*-\s*/, '')))
      .filter(t => t && !t.startsWith('.codebase-memory/')); // generated index, changes on every rebuild
    return { file: path.join('.trail', 'learnings', f), title, touches };
  });
}

/** Learnings mentioning `rel` whose file changed in a commit after the learning was added. */
function staleFor(root, rel, learnings = readLearnings(root)) {
  const out = [];
  for (const l of learnings) {
    if (!l.touches.includes(rel)) continue;
    let added;
    try { added = git(root, ['log', '--diff-filter=A', '--format=%H', '-1', '--', l.file]); } catch { continue; }
    if (!added) continue; // not committed yet: written this session, so fresh
    const commits = git(root, ['log', '--format=%h %s', `${added}..HEAD`, '--', rel]);
    if (commits) out.push({ title: l.title, learning: l.file, file: rel, count: commits.split('\n').length, latest: commits.split('\n')[0] });
  }
  return out;
}

const describe = s =>
  `trail learning "${s.title}" mentions ${s.file}, but ${s.count} commit(s) changed it since (latest: ${s.latest}). Treat it as NEEDS RE-CHECK, not fact. (${s.learning})`;

function main() {
  if (process.argv.includes('--all')) {
    const root = git(process.cwd(), ['rev-parse', '--show-toplevel']);
    const learnings = readLearnings(root);
    const files = [...new Set(learnings.flatMap(l => l.touches))];
    const stale = files.flatMap(f => staleFor(root, f, learnings));
    console.log(stale.length ? stale.map(describe).join('\n') : 'All learnings are fresh.');
    return;
  }
  let input;
  try { input = JSON.parse(fs.readFileSync(0, 'utf8')); } catch { return; }
  const target = input.tool_input?.file_path;
  if (!target) return;
  const root = git(input.cwd || process.cwd(), ['rev-parse', '--show-toplevel']);
  const rel = path.relative(root, path.resolve(input.cwd || root, target));
  if (rel.startsWith('..')) return;

  // Warn once per session per learning+file, so repeated reads cost no tokens.
  const seenPath = path.join(os.tmpdir(), `trail-stale-${String(input.session_id || 'none').replace(/\W/g, '')}.json`);
  let seen = [];
  try { seen = JSON.parse(fs.readFileSync(seenPath, 'utf8')); } catch {}
  const fresh = staleFor(root, rel).filter(s => !seen.includes(`${s.learning}|${s.file}`));
  if (!fresh.length) return;
  try { fs.writeFileSync(seenPath, JSON.stringify([...seen, ...fresh.map(s => `${s.learning}|${s.file}`)])); } catch {}
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: { hookEventName: 'PreToolUse', additionalContext: fresh.map(describe).join('\n') },
  }));
}

module.exports = { readLearnings, staleFor };
// shortcut: only Read/Edit/Write trigger it; files read via Bash (cat, sed) are not checked.
// shortcut: file-level, so any later commit to a file flags the learning even if the part it
// describes is untouched; move to symbol-level hashes if false "re-check" warnings pile up.
if (require.main === module) { try { main(); } catch { /* never block a tool call */ } }

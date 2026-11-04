#!/usr/bin/env node
// Self-check for trail-stale.cjs in a throwaway git repo. Run: node .claude/hooks/trail-stale.test.cjs
const assert = require('assert');
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { staleFor } = require('./trail-stale.cjs');

const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'trail-stale-test-')));
const sh = (...args) => execFileSync('git', args, { cwd: root, stdio: 'ignore' });
const write = (rel, text) => { fs.mkdirSync(path.dirname(path.join(root, rel)), { recursive: true }); fs.writeFileSync(path.join(root, rel), text); };
const learning = (title, touches) => `---\ntitle: ${title}\ntouches:\n${touches.map(t => `  - "${t}"`).join('\n')}\n---\n\n## Decided\n- x\n`;

sh('init', '-q'); sh('config', 'user.email', 't@t'); sh('config', 'user.name', 't');
write('src/a.js', 'v1'); write('src/b.js', 'v1');
write('.trail/learnings/one.md', learning('About a', ['src/a.js', 'src/b.js']));
sh('add', '.'); sh('commit', '-qm', 'code + learning');

assert.deepStrictEqual(staleFor(root, 'src/a.js'), [], 'fresh right after the learning is committed');

write('src/a.js', 'v2'); sh('commit', '-qam', 'change a');
const stale = staleFor(root, 'src/a.js');
assert.strictEqual(stale.length, 1, 'a.js changed after the learning, so it is stale');
assert.strictEqual(stale[0].count, 1);
assert.match(stale[0].latest, /change a/);
assert.deepStrictEqual(staleFor(root, 'src/b.js'), [], 'b.js unchanged, so still fresh');
assert.deepStrictEqual(staleFor(root, 'src/other.js'), [], 'file no learning mentions');

write('.trail/learnings/two.md', learning('Uncommitted', ['src/a.js']));
assert.strictEqual(staleFor(root, 'src/a.js').length, 1, 'uncommitted learning counts as fresh');

// Hook mode: prints once, then stays silent for the same session.
const hook = file => execFileSync('node', [path.join(__dirname, 'trail-stale.cjs')], {
  input: JSON.stringify({ cwd: root, session_id: `test${process.pid}`, tool_input: { file_path: path.join(root, file) } }),
  encoding: 'utf8',
});
const first = hook('src/a.js');
assert.match(JSON.parse(first).hookSpecificOutput.additionalContext, /NEEDS RE-CHECK/);
assert.strictEqual(hook('src/a.js'), '', 'second read in the same session is silent');
assert.strictEqual(hook('src/b.js'), '', 'fresh file prints nothing');

fs.rmSync(root, { recursive: true, force: true });
fs.rmSync(path.join(os.tmpdir(), `trail-stale-test${process.pid}.json`), { force: true });
console.log('trail-stale: all checks passed');

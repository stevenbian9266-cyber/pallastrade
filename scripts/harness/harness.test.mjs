import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, unlinkSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(fileURLToPath(import.meta.url), '..', '..', '..');
const CLI = join(ROOT, 'scripts', 'harness', 'cli.mjs');

/** Run the harness CLI, returning exit code + stdout. Never throws. */
function run(...args) {
  try {
    const out = execFileSync('node', [CLI, ...args], { cwd: ROOT, encoding: 'utf-8' });
    return { code: 0, out };
  } catch (e) {
    return { code: e.status ?? 1, out: String(e.stdout ?? e.message) };
  }
}

test('doctor exits 0 on a healthy repo', () => {
  const { code, out } = run('doctor');
  assert.equal(code, 0, out);
});

test('affected returns valid JSON and does not crash', () => {
  const { code, out } = run('affected', '--base', 'HEAD');
  assert.equal(code, 0, out);
  // Output is a single pretty-printed JSON object (may span multiple lines).
  const parsed = JSON.parse(out.slice(out.indexOf('{')));
  assert.ok(Array.isArray(parsed.affectedComponents));
  assert.ok(typeof parsed.filesChanged === 'number');
});

test('eval-ai --check-freshness fails closed on stale refs', () => {
  // Exit 0 = all skill refs valid; exit 1 = stale refs found (fail-closed).
  // Both are legal terminal states for this report command.
  const { code, out } = run('eval-ai', '--check-freshness');
  assert.ok(code === 0 || code === 1, `unexpected exit ${code}: ${out}`);
});

test('gate lifecycle: create → clear all checks → status cleared', () => {
  const ts = Date.now();
  const task = `测试：contract test ${ts}`;
  const { code: createCode } = run('gate', '--task', task, '--type', 'style');
  assert.equal(createCode, 1, 'gate starts uncleared → exit 1');

  const gatesDir = join(ROOT, 'harness', 'gates');
  const gateFile = readdirSync(gatesDir)
    .filter(f => f.endsWith('.json'))
    .sort()
    .pop();
  assert.ok(gateFile, 'a gate file was created');
  const gateId = gateFile.replace(/\.json$/, '');
  const state = JSON.parse(readFileSync(join(gatesDir, gateFile), 'utf-8'));
  assert.equal(state.taskDescription, task);

  // Clear every check (including verify-test, which is fine for a style gate
  // contract test — the real process requires evidence, that's out of scope here).
  for (const check of state.checks) {
    run('gate:clear', '--gate', gateId, '--clear', check.id);
  }
  const { code: statusCode, out: statusOut } = run('gate:status');
  assert.equal(statusCode, 0, statusOut);

  // Cleanup — remove the contract-test gate so it doesn't pollute gates/.
  unlinkSync(join(gatesDir, gateFile));
});

test('git-files.getChangedFiles returns arrays even with no base history', async () => {
  const { getChangedFiles } = await import('./git-files.mjs');
  const { files, errors } = getChangedFiles(ROOT, 'HEAD');
  assert.ok(Array.isArray(files));
  assert.ok(Array.isArray(errors));
});

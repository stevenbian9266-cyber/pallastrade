import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, unlinkSync, readdirSync, mkdirSync, writeFileSync, rmSync, renameSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(fileURLToPath(import.meta.url), '..', '..', '..');
const CLI = join(ROOT, 'scripts', 'harness', 'cli.mjs');
const SCANNER = join(ROOT, 'scripts', 'harness', 'scan-anti-patterns.mjs');

/** Run the harness CLI, returning exit code + stdout. Never throws. */
function run(...args) {
  try {
    const out = execFileSync('node', [CLI, ...args], { cwd: ROOT, encoding: 'utf-8' });
    return { code: 0, out };
  } catch (e) {
    return { code: e.status ?? 1, out: String(e.stdout ?? e.message) };
  }
}

/** Run the anti-pattern scanner on specific files (relative to ROOT). */
function runScan(...files) {
  try {
    const out = execFileSync('node', [SCANNER, 'scan', '--files', files.join(',')], { cwd: ROOT, encoding: 'utf-8' });
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

test('AP-009a guard-aware: guarded static redirect passes, unguarded fails', () => {
  // NOTE: temp dir must NOT start with '.' — glob skips dot-directories, so
  // dot-prefixed files would silently never be scanned.
  const tmpDir = join(ROOT, 'storefront', 'src', 'harness-tmp');
  mkdirSync(tmpDir, { recursive: true });
  const guarded = 'storefront/src/harness-tmp/guarded.ts';
  const unguarded = 'storefront/src/harness-tmp/unguarded.ts';
  try {
    writeFileSync(join(ROOT, guarded),
      'export function f() {\n  if (target !== currentPath) {\n    redirect("/us/en");\n  }\n}\n');
    writeFileSync(join(ROOT, unguarded),
      'export function g() {\n  redirect("/us/en");\n}\n');

    // Guarded redirect — scanner must not flag it (exit 0).
    const guardedRes = runScan(guarded);
    assert.equal(guardedRes.code, 0, `guarded redirect flagged:\n${guardedRes.out}`);

    // Unguarded static redirect — scanner must fail-closed (exit 1).
    const unguardedRes = runScan(unguarded);
    assert.equal(unguardedRes.code, 1, `unguarded redirect not flagged:\n${unguardedRes.out}`);
    assert.match(unguardedRes.out, /AP-009a/);

    // Dynamic (template-literal) redirect — not a violation either.
    writeFileSync(join(ROOT, guarded),
      'export function h(p: string) {\n  redirect(`/${p}/fallback`);\n}\n');
    const dynamicRes = runScan(guarded);
    assert.equal(dynamicRes.code, 0, `dynamic redirect flagged:\n${dynamicRes.out}`);
  } finally {
    rmSync(tmpDir, { recursive: true, force: true });
  }
});

test('gate:required blocks when no cleared gate exists for this branch', () => {
  const gatesDir = join(ROOT, 'harness', 'gates');
  const files = readdirSync(gatesDir).filter(f => f.endsWith('.json'));
  if (files.length === 0) {
    // Nothing to move — the check should still fail with no gates present.
    const res = run('gate:required');
    assert.equal(res.code, 1);
    return;
  }
  const tmp = join(ROOT, 'harness', 'gates-tmp');
  mkdirSync(tmp, { recursive: true });
  for (const f of files) renameSync(join(gatesDir, f), join(tmp, f));
  try {
    const res = run('gate:required');
    assert.equal(res.code, 1, `expected block, got:\n${res.out}`);
    assert.match(res.out, /no cleared/);
  } finally {
    for (const f of readdirSync(tmp)) renameSync(join(tmp, f), join(gatesDir, f));
    rmSync(tmp, { recursive: true, force: true });
  }
});

test('prd lifecycle: new creates skeleton, verify ignores commented template ACs', () => {
  const ts = Date.now();
  const title = `测试：PRD contract ${ts}`;
  const { code: newCode, out: newOut } = run('prd', 'new', '--title', title);
  assert.equal(newCode, 0, newOut);
  assert.match(newOut, /PRD 骨架已创建/);

  const rel = newOut.match(/docs[\\/]prd[\\/][^\s]+\.md/);
  assert.ok(rel, `PRD file path reported: ${newOut}`);
  const filePath = rel[0];
  const id = filePath.split(/[\\/]/).pop().replace(/\.md$/, '');

  try {
    const { code: listCode, out: listOut } = run('prd', 'list');
    assert.equal(listCode, 0, listOut);
    assert.match(listOut, new RegExp(id));

    // Skeleton has no real AC (template examples live in HTML comments) →
    // verify must warn and exit 1 instead of counting template examples.
    const { code: verifyCode, out: verifyOut } = run('prd', 'verify', '--id', id);
    assert.equal(verifyCode, 1, verifyOut);
    assert.match(verifyOut, /未找到 AC/);
  } finally {
    unlinkSync(join(ROOT, filePath));
  }
});

test('sync-check reports assets or passes, and --ack always passes', () => {
  // With working-tree changes present it lists assets (exit 1); with none it
  // passes (exit 0). Both are legal — the contract is "never crashes".
  const res = run('sync-check');
  assert.ok(res.code === 0 || res.code === 1, `unexpected exit ${res.code}: ${res.out}`);

  // --ack confirms evaluation and always passes.
  const ack = run('sync-check', '--ack');
  assert.equal(ack.code, 0, ack.out);
});

test('nav:check validates the AGENTS.md §0 navigation map', () => {
  const res = run('nav:check');
  assert.equal(res.code, 0, res.out);
  assert.match(res.out, /导航地图/);
});

test('prd verify --allow-missing-tests passes for deletion-style PRDs', () => {
  const ts = Date.now();
  const title = `测试：PRD allow-missing ${ts}`;
  const { code: newCode, out: newOut } = run('prd', 'new', '--title', title);
  assert.equal(newCode, 0, newOut);
  const rel = newOut.match(/docs[\\/]prd[\\/][^\s]+\.md/);
  assert.ok(rel, `PRD path reported: ${newOut}`);
  const filePath = rel[0];
  const id = filePath.split(/[\\/]/).pop().replace(/\.md$/, '');
  try {
    // No real AC → verify fails by default…
    const fail = run('prd', 'verify', '--id', id);
    assert.equal(fail.code, 1, fail.out);
    // …but --allow-missing-tests (deletion/refactor tasks) passes.
    const pass = run('prd', 'verify', '--id', id, '--allow-missing-tests');
    assert.equal(pass.code, 0, pass.out);
  } finally {
    unlinkSync(join(ROOT, filePath));
  }
});

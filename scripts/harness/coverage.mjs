#!/usr/bin/env node
/**
 * Coverage gate — parses coverage artifacts and compares against thresholds
 * declared in harness/config.json (coverage.thresholds).
 *
 *   node scripts/harness/cli.mjs coverage [--component backend|storefront|platform] [--enforce]
 *
 * Sources:
 *   - backend  : SimpleCov Cobertura XML  (coverage/cobertura-coverage.xml)
 *   - storefront / platform : vitest v8 JSON summary (coverage/coverage-summary.json)
 *
 * Exit codes:
 *   0 — all present components meet thresholds (or no data & !enforce)
 *   1 — a component is below threshold, or (--enforce) a required component has no data
 */
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

function loadConfig(rootDir) {
  const p = resolve(rootDir, 'harness', 'config.json');
  if (!existsSync(p)) return null;
  try { return JSON.parse(readFileSync(p, 'utf-8')); } catch { return null; }
}

/** SimpleCov Cobertura: <coverage line-rate="0.85" branch-rate="0.6" ...> */
function parseCobertura(file) {
  const xml = readFileSync(file, 'utf-8');
  const m = xml.match(/<coverage[^>]*line-rate="([\d.]+)"[^>]*branch-rate="([\d.]+)"/);
  if (!m) return null;
  return { line: parseFloat(m[1]) * 100, branch: parseFloat(m[2]) * 100 };
}

/** vitest v8: { total: { lines: { pct }, statements: { pct }, functions: { pct }, branches: { pct } } } */
function parseV8Summary(file) {
  const j = JSON.parse(readFileSync(file, 'utf-8'));
  const t = j?.total;
  if (!t) return null;
  return {
    lines: t.lines?.pct,
    statements: t.statements?.pct,
    functions: t.functions?.pct,
    branches: t.branches?.pct,
  };
}

const COMPONENT_DEFS = {
  backend: {
    files: ['backend/coverage/cobertura-coverage.xml', 'coverage/cobertura-coverage.xml'],
    parser: parseCobertura,
  },
  storefront: {
    files: ['storefront/coverage/coverage-summary.json', 'storefront/coverage/coverage-final.json'],
    parser: parseV8Summary,
  },
  platform: {
    files: ['platform/coverage/coverage-summary.json'],
    parser: parseV8Summary,
  },
};

export function run({ rootDir, args }) {
  const enforce = args.includes('--enforce');
  const componentArg = args.includes('--component') ? args[args.indexOf('--component') + 1] : null;
  const config = loadConfig(rootDir);
  const thresholds = config?.coverage?.thresholds || {};
  const components = componentArg ? [componentArg] : Object.keys(COMPONENT_DEFS);

  let failed = false;

  for (const comp of components) {
    const def = COMPONENT_DEFS[comp];
    if (!def) {
      console.log(`⚠️  coverage: unknown component "${comp}". Valid: ${Object.keys(COMPONENT_DEFS).join(', ')}`);
      continue;
    }

    const file = def.files.find(f => existsSync(resolve(rootDir, f)));
    if (!file) {
      const msg = `coverage: no data for ${comp} (looked for ${def.files.join(' or ')}). Run tests with coverage first.`;
      if (enforce) { console.log(`❌ ${msg}`); failed = true; }
      else console.log(`ℹ️  ${msg}`);
      continue;
    }

    const data = def.parser(resolve(rootDir, file));
    if (!data) {
      const msg = `coverage: unparseable data for ${comp} at ${file}`;
      if (enforce) { console.log(`❌ ${msg}`); failed = true; }
      else console.log(`ℹ️  ${msg}`);
      continue;
    }

    const th = thresholds[comp] || {};
    const checks = [];
    if (data.line !== undefined && data.line !== null) checks.push({ k: 'line', v: data.line, t: th.line ?? 0 });
    if (data.lines !== undefined && data.lines !== null) checks.push({ k: 'lines', v: data.lines, t: th.lines ?? 0 });
    if (data.branch !== undefined && data.branch !== null) checks.push({ k: 'branch', v: data.branch, t: th.branch ?? 0 });
    if (data.branches !== undefined && data.branches !== null) checks.push({ k: 'branches', v: data.branches, t: th.branches ?? 0 });
    if (data.functions !== undefined && data.functions !== null) checks.push({ k: 'functions', v: data.functions, t: th.functions ?? 0 });

    let ok = checks.length > 0;
    const parts = checks.map(c => {
      const pass = c.v >= c.t;
      if (!pass) ok = false;
      return `${c.k} ${c.v.toFixed(1)}% (threshold ${c.t}%)${pass ? '' : ' ❌'}`;
    });
    console.log(`${ok ? '✅' : '❌'} coverage ${comp}: ${parts.join(', ')}`);
    if (!ok) failed = true;
  }

  process.exit(failed ? 1 : 0);
}

// CLI entry
const args = process.argv.slice(2);
if (args.length > 0 && args[0] === 'coverage') {
  run({ rootDir: resolve(import.meta.dirname, '..', '..'), args: args.slice(1) });
}

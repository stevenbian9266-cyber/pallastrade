#!/usr/bin/env node
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync } from 'node:child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..', '..');

const args = process.argv.slice(2);
const cmd = args[0];

function getArg(args, flag) {
  const idx = args.indexOf(flag);
  return idx >= 0 ? args[idx + 1] : null;
}

function hasArg(args, flag) {
  return args.includes(flag);
}

// ================================================================
// doctor
// ================================================================
if (cmd === 'doctor') {
  const fixSafe = hasArg(args, '--fix-safe');
  const format = getArg(args, '--format') || 'human';

  const checks = [
    {
      name: 'git-repo',
      run: () => { execSync('git rev-parse --git-dir', { cwd: ROOT, stdio: 'pipe' }); return { pass: true, detail: 'Git repo detected' }; },
      onError: () => ({ pass: false, detail: 'NOT a git repo', fix: 'Run `git init`' }),
    },
    {
      name: 'node-version',
      run: () => {
        const v = parseInt(process.version.slice(1));
        return v >= 22 ? { pass: true, detail: `Node ${process.version}` }
          : { pass: false, detail: `Node ${process.version} (need >=22)`, fix: 'Install Node.js 22+' };
      },
    },
    {
      name: 'dir-backend',
      run: () => existsSync(resolve(ROOT, 'backend')) ? { pass: true, detail: 'backend/ exists' } : { pass: false, detail: 'backend/ MISSING' },
    },
    {
      name: 'dir-platform',
      run: () => existsSync(resolve(ROOT, 'platform')) ? { pass: true, detail: 'platform/ exists' } : { pass: false, detail: 'platform/ MISSING' },
    },
    {
      name: 'dir-storefront',
      run: () => existsSync(resolve(ROOT, 'storefront')) ? { pass: true, detail: 'storefront/ exists' } : { pass: false, detail: 'storefront/ MISSING' },
    },
    {
      name: 'dir-ai',
      run: () => existsSync(resolve(ROOT, 'ai')) ? { pass: true, detail: 'ai/ exists' } : { pass: false, detail: 'ai/ MISSING' },
    },
    {
      name: 'agents-md',
      run: () => existsSync(resolve(ROOT, 'AGENTS.md')) ? { pass: true, detail: 'AGENTS.md exists at root' }
        : { pass: false, detail: 'AGENTS.md missing', fix: 'Create AGENTS.md at repository root' },
    },
    {
      name: 'compose-file',
      run: () => {
        const candidates = ['backend/docker-compose.dev.yml', 'backend/docker-compose.yml', 'docker-compose.yml'];
        const found = candidates.find(f => existsSync(resolve(ROOT, f)));
        return found ? { pass: true, detail: `Compose found: ${found}` }
          : { pass: false, detail: 'No docker-compose file found' };
      },
    },
    {
      name: 'vscode-tasks',
      run: () => {
        const p = resolve(ROOT, '.vscode', 'tasks.json');
        if (!existsSync(p)) return { pass: true, detail: 'No tasks.json' };
        const content = readFileSync(p, 'utf-8');
        return (content.includes('D:\\\\') || content.includes('D:/'))
          ? { pass: false, detail: 'tasks.json contains absolute paths', fix: 'Replace with harness CLI calls' }
          : { pass: true, detail: 'No absolute paths detected' };
      },
    },
    {
      name: 'storefront-lockfile',
      run: () => {
        const npmLock = existsSync(resolve(ROOT, 'storefront', 'package-lock.json'));
        const pnpmLock = existsSync(resolve(ROOT, 'storefront', 'pnpm-lock.yaml'));
        if (npmLock && pnpmLock) return { pass: false, detail: 'Both package-lock.json and pnpm-lock.yaml exist', fix: 'Standardize on pnpm: delete package-lock.json' };
        return { pass: true, detail: pnpmLock ? 'pnpm-lock.yaml only' : 'package-lock.json only' };
      },
    },
    {
      name: 'harness-dirs',
      run: () => {
        const dirs = ['harness/policies', 'harness/scenarios', 'harness/versions', 'harness/baselines', 'scripts/harness'];
        const missing = dirs.filter(d => !existsSync(resolve(ROOT, d)));
        if (missing.length > 0) {
          if (fixSafe) {
            for (const d of missing) mkdirSync(resolve(ROOT, d), { recursive: true });
            return { pass: true, detail: `${missing.length} missing dirs created` };
          }
          return { pass: false, detail: `${missing.length} harness dirs missing: ${missing.join(', ')}`, fix: 'Run with --fix-safe' };
        }
        return { pass: true, detail: 'All harness directories present' };
      },
    },
  ];

  const results = [];
  for (const check of checks) {
    try {
      results.push({ name: check.name, ...check.run() });
    } catch (e) {
      results.push(check.onError ? check.onError() : { name: check.name, pass: false, detail: e.message });
    }
  }

  const failed = results.filter(r => !r.pass);
  if (format === 'json') {
    console.log(JSON.stringify({ status: failed.length === 0 ? 'healthy' : 'issues', results }, null, 2));
  } else {
    for (const r of results) {
      console.log(`${r.pass ? '✅' : '❌'} ${r.name}: ${r.detail}`);
      if (r.fix && fixSafe) console.log(`   ↳ fix: ${r.fix}`);
    }
    console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
    if (failed.length > 0 && !fixSafe) {
      console.log('Run with --fix-safe to auto-fix safe issues.');
    }
  }
  process.exit(failed.length > 0 ? 1 : 0);
}

// ================================================================
// affected
// ================================================================
else if (cmd === 'affected') {
  const base = getArg(args, '--base') || 'origin/main';
  try {
    const changed = execSync(`git diff --name-only ${base}...HEAD`, { cwd: ROOT, encoding: 'utf-8' }).trim();
    const files = changed ? changed.split('\n').filter(Boolean) : [];
    const components = new Set();
    for (const f of files) {
      if (f.startsWith('backend/')) components.add('backend');
      else if (f.startsWith('platform/')) components.add('platform');
      else if (f.startsWith('storefront/')) components.add('storefront');
      else if (f.startsWith('ai/')) components.add('ai');
    }
    console.log(JSON.stringify({ filesChanged: files.length, affectedComponents: [...components], estimatedTests: files.length * 3 }, null, 2));
  } catch {
    console.log(JSON.stringify({ filesChanged: 0, affectedComponents: [], estimatedTests: 0 }));
  }
}

// ================================================================
// check
// ================================================================
else if (cmd === 'check') {
  const profile = getArg(args, '--profile') || 'quick';
  console.log(`[harness] check --profile ${profile}`);
  console.log('[harness] CI workflows handle full profile execution in GitHub Actions.');
  console.log('[harness] Run `harness doctor` for local environment checks.');
}

// ================================================================
// eval-ai
// ================================================================
else if (cmd === 'eval-ai' || cmd === 'eval') {
  await import('./eval-ai.mjs').then(m => m.run({ rootDir: ROOT, args }));
}

// ================================================================
// generated:check
// ================================================================
else if (cmd === 'generated:check') {
  await import('./generated-check.mjs').then(m => m.check({ rootDir: ROOT }));
}

// ================================================================
// doc-impact
// ================================================================
else if (cmd === 'doc-impact') {
  await import('./doc-impact.mjs').then(m => m.run({ rootDir: ROOT, args }));
}

// ================================================================
// e2e
// ================================================================
else if (cmd === 'e2e') {
  const target = args[1];
  console.log(`[harness] e2e ${target} — CI handles execution.`);
}

// ================================================================
// upgrade:*
// ================================================================
else if (cmd === 'upgrade:audit') {
  await import('./upgrade-audit.mjs').then(m => m.audit({ rootDir: ROOT, args }));
}
else if (cmd === 'upgrade:baseline') {
  await import('./upgrade-verify.mjs').then(m => m.baseline({ rootDir: ROOT, args }));
}
else if (cmd === 'upgrade:verify') {
  await import('./upgrade-verify.mjs').then(m => m.verify({ rootDir: ROOT }));
}
else if (cmd === 'upgrade:rollback') {
  await import('./upgrade-rollback.mjs').then(m => m.rollback({ rootDir: ROOT }));
}
else if (cmd === 'upgrade:evidence') {
  await import('./upgrade-verify.mjs').then(m => m.evidence({ rootDir: ROOT }));
}

// ================================================================
// evidence / diagnostics
// ================================================================
else if (cmd === 'evidence') {
  console.log('[harness] evidence — CI handles collection.');
}
else if (cmd === 'diagnostics') {
  console.log('[harness] diagnostics — CI handles collection.');
}

// ================================================================
// help
// ================================================================
else {
  console.log(`PallasTrade Harness CLI

Usage: node scripts/harness/cli.mjs <command> [options]

Environment:
  doctor [--fix-safe] [--format json]   Diagnose local dev environment

Analysis:
  affected --base origin/main           Show affected components

Quality:
  check --profile quick|full|release    Run quality gates
  e2e dashboard|storefront              Run end-to-end tests
  eval-ai --check-freshness             Verify skill path validity
  generated:check                       Check generated files for drift
  doc-impact --base origin/main         Check knowledge docs are synced

Upgrade:
  upgrade:audit --from X --to Y         Analyze upgrade impact
  upgrade:baseline --save                Save test baseline
  upgrade:verify                        Compare against baseline
  upgrade:rollback                      Atomic rollback
  upgrade:evidence                      Generate delivery evidence

Evidence:
  evidence collect                      Collect structured evidence
  diagnostics collect                   Collect failure diagnostics
`);
}

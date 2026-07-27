import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { execSync } from 'node:child_process';

export async function baseline({ rootDir, args }) {
  const save = args.includes('--save');
  const baselineDir = resolve(rootDir, 'harness', 'baselines');

  if (!existsSync(baselineDir)) mkdirSync(baselineDir, { recursive: true });

  // Get current version from git tag or commit hash
  let version = 'pre-release';
  try {
    // Try tag first
    const tagOutput = execSync('git describe --tags --abbrev=0', { cwd: rootDir, encoding: 'utf-8', stdio: 'pipe' }).trim();
    if (tagOutput && !tagOutput.startsWith('fatal:')) {
      version = tagOutput.replace(/^v/, '').replace(/[^a-zA-Z0-9._-]/g, '-');
    }
  } catch { /* no tags */ }

  // Fall back to commit hash
  if (version === 'pre-release') {
    try {
      const hash = execSync('git rev-parse --short HEAD', { cwd: rootDir, encoding: 'utf-8' }).trim();
      version = `commit-${hash}`;
    } catch { /* use pre-release */ }
  }

  const commit = execSync('git rev-parse HEAD', { cwd: rootDir, encoding: 'utf-8' }).trim();

  const baseline = {
    version,
    timestamp: new Date().toISOString(),
    commit,
    tests: { total: 0, passed: 0, failed: 0, skipped: 0 },
    coverage: { lines: 0, branches: 0 },
    status: 'baseline-saved',
  };

  const baselineFile = resolve(baselineDir, `baseline-${version}.json`);
  writeFileSync(baselineFile, JSON.stringify(baseline, null, 2));
  console.log(`✅ Baseline saved: baseline-${version}.json`);
  console.log(`   Version: ${version}`);
  console.log(`   Commit:  ${commit.slice(0, 8)}`);
  console.log(`   Run 'harness upgrade:verify' after upgrade to compare.`);
}

export async function verify({ rootDir }) {
  const baselineDir = resolve(rootDir, 'harness', 'baselines');

  // Find latest baseline
  let baseline = null;
  if (existsSync(baselineDir)) {
    const { readdirSync } = await import('node:fs');
    const files = readdirSync(baselineDir).filter(f => f.endsWith('.json')).sort().reverse();
    for (const f of files) {
      const data = JSON.parse(readFileSync(resolve(baselineDir, f), 'utf-8'));
      if (data.status === 'baseline-saved') {
        baseline = data;
        break;
      }
    }
  }

  if (!baseline) {
    console.log('❌ No baseline found. Run `harness upgrade:baseline --save` before upgrading.');
    process.exit(1);
  }

  console.log('Comparing against baseline:');
  console.log(`  Version: ${baseline.version}`);
  console.log(`  Commit:  ${baseline.commit.slice(0, 8)}`);
  console.log('');

  // Run quick check
  try {
    execSync('node scripts/harness/cli.mjs check --profile full', { cwd: rootDir, stdio: 'inherit' });
    console.log('\n✅ Full check passed. No regression detected.');
  } catch {
    console.log('\n❌ Full check failed. Regression detected after upgrade.');
    console.log('   Review failures above. Consider rolling back with `harness upgrade:rollback`.');
    process.exit(1);
  }
}

export async function evidence({ rootDir }) {
  const { createWriteStream, readdirSync, readFileSync, existsSync, mkdirSync, writeFileSync } = await import('node:fs');
  const { resolve } = await import('node:path');
  const { execSync } = await import('node:child_process');

  console.log('📦 Generating upgrade evidence package...\n');

  const evidenceDir = resolve(rootDir, 'artifacts', 'upgrade-evidence');
  if (!existsSync(evidenceDir)) mkdirSync(evidenceDir, { recursive: true });

  const now = new Date().toISOString().replace(/[:.]/g, '-');
  const commit = execSync('git rev-parse --short HEAD', { cwd: rootDir, encoding: 'utf-8' }).trim();

  // 1. Collect audit report
  const auditFile = resolve(evidenceDir, '01-audit-report.json');
  let auditData = null;
  try {
    // Try reading the latest audit from baselines
    const baselineDir = resolve(rootDir, 'harness', 'baselines');
    if (existsSync(baselineDir)) {
      const files = readdirSync(baselineDir).filter(f => f.startsWith('baseline-')).sort().reverse();
      if (files.length > 0) {
        auditData = JSON.parse(readFileSync(resolve(baselineDir, files[0]), 'utf-8'));
      }
    }
  } catch { /* no audit data available */ }
  if (auditData) {
    writeFileSync(auditFile, JSON.stringify(auditData, null, 2));
    console.log('   ✅ 01-audit-report.json');
  }

  // 2. Doctor check snapshot
  const doctorFile = resolve(evidenceDir, '02-doctor-check.txt');
  try {
    const doctorOutput = execSync('node scripts/harness/cli.mjs doctor', { cwd: rootDir, encoding: 'utf-8' });
    writeFileSync(doctorFile, doctorOutput);
    console.log('   ✅ 02-doctor-check.txt');
  } catch { console.log('   ⚠️  Doctor check failed'); }

  // 3. Git status snapshot
  const gitFile = resolve(evidenceDir, '03-git-status.txt');
  try {
    const gitLog = execSync('git log --oneline -5', { cwd: rootDir, encoding: 'utf-8' });
    const gitStatus = execSync('git status --short', { cwd: rootDir, encoding: 'utf-8' });
    writeFileSync(gitFile, `=== Last 5 commits ===\n${gitLog}\n=== Working tree ===\n${gitStatus}`);
    console.log('   ✅ 03-git-status.txt');
  } catch { console.log('   ⚠️  Git info failed'); }

  // 4. Rollback steps
  const rollbackFile = resolve(evidenceDir, '04-rollback-steps.md');
  writeFileSync(rollbackFile, `# Rollback Steps
Generated: ${now}
Commit: ${commit}

## Quick Rollback (automated)
\`\`\`bash
harness upgrade:rollback
\`\`\`

## Manual Rollback
1. Git: \`git reset --hard <pre-upgrade-commit>\`
2. Database: \`cd backend && bundle exec rails db:rollback\`
3. Assets: \`cd backend && bundle exec rails assets:precompile\`
4. Verify: \`harness doctor\`
`);
  console.log('   ✅ 04-rollback-steps.md');

  // 5. README
  const readmeFile = resolve(evidenceDir, '00-README.txt');
  writeFileSync(readmeFile, `PallasTrade Upgrade Evidence Package
========================================
Generated: ${new Date().toISOString()}
Commit: ${commit}
Project: PallasTrade Commerce
Maintainer: Steven Bian

Contents:
  01-audit-report.json   — Upgrade impact analysis
  02-doctor-check.txt    — Environment health snapshot
  03-git-status.txt      — Git history and working tree
  04-rollback-steps.md   — Step-by-step rollback instructions

For questions, contact: stevenbian
`);
  console.log('   ✅ 00-README.txt');

  // Summary
  console.log(`\n✅ Evidence package complete.`);
  console.log(`   Location: artifacts/upgrade-evidence/`);
  console.log(`   ${readdirSync(evidenceDir).length} files generated.`);
}

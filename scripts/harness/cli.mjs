#!/usr/bin/env node
import { existsSync, readFileSync, writeFileSync, mkdirSync, readdirSync, unlinkSync } from 'node:fs';
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
        const dirs = ['harness/policies', 'harness/scenarios', 'scripts/harness'];
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
  const { files, errors } = await import('./git-files.mjs').then(m => m.getChangedFiles(ROOT, base));
  const components = new Set();
  for (const f of files) {
    if (f.startsWith('backend/')) components.add('backend');
    else if (f.startsWith('platform/')) components.add('platform');
    else if (f.startsWith('storefront/')) components.add('storefront');
    else if (f.startsWith('ai/')) components.add('ai');
    else if (f.startsWith('harness/') || f.startsWith('scripts/') || f.startsWith('.github/')) components.add('harness');
  }
  console.log(JSON.stringify({ filesChanged: files.length, affectedComponents: [...components], errors, estimatedTests: files.length * 3 }, null, 2));
}

// ================================================================
// check
// ================================================================
else if (cmd === 'check') {
  const profile = getArg(args, '--profile') || 'quick';
  console.log(`[harness] check --profile ${profile}`);

  // Load profile config
  const configPath = resolve(ROOT, 'harness', 'config.json');
  const profiles = existsSync(configPath)
    ? JSON.parse(readFileSync(configPath, 'utf-8')).profiles
    : {};
  const profileChecks = profiles[profile]?.checks || ['degraded-loop'];

  console.log(`[harness] Running: ${profileChecks.join(', ')}`);
  let exitCode = 0;

  for (const checkName of profileChecks) {
    try {
      if (checkName === 'anti-patterns') {
        await import('./scan-anti-patterns.mjs').then(m => m.scan({ rootDir: ROOT }));
      } else if (checkName === 'degraded-loop') {
        const result = await import('./check-degraded-loop.mjs').then(m => m.scan({ rootDir: ROOT }));
        if (result.errors > 0) exitCode = 1;
      } else if (checkName === 'doc-impact') {
        await import('./doc-impact.mjs').then(m => m.run({ rootDir: ROOT, args: ['--base', 'origin/main'] }));
      } else if (checkName === 'ai-freshness') {
        await import('./eval-ai.mjs').then(m => m.run({ rootDir: ROOT, args: ['--check-freshness'] }));
      } else if (checkName === 'generated-check') {
        await import('./generated-check.mjs').then(m => m.check({ rootDir: ROOT }));
      } else {
        console.log(`[harness] ⏭  ${checkName}: delegated to CI / external runner`);
      }
    } catch (e) {
      console.error(`[harness] ❌ ${checkName} failed: ${e.message}`);
      exitCode = 1;
    }
  }

  if (exitCode !== 0) process.exitCode = exitCode;
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
// evidence / diagnostics
// ================================================================
else if (cmd === 'evidence') {
  await import('./evidence.mjs').then(m => m.collect({ rootDir: ROOT }));
}
else if (cmd === 'diagnostics') {
  console.log('[harness] diagnostics — CI handles collection.');
}

// ================================================================
// gate — MANDATORY pre-coding gate
// ================================================================
else if (cmd === 'gate') {
  const taskDesc = getArg(args, '--task') || args[1] || 'unspecified';
  let taskType = getArg(args, '--type');

  // Prefix → task type auto-detection
  const PREFIX_MAP = {
    '修复：': 'bugfix',   'fix:': 'bugfix',
    '优化：': 'feature',  '改进：': 'feature',
    '新增：': 'feature',  '添加：': 'feature',
    '样式：': 'style',    'style:': 'style',
    '需求：': 'feature',
    '审计：': 'audit',    'audit:': 'audit',
    '研究：': 'research', '调研：': 'research', 'research:': 'research',
    '文档：': 'docs',     'docs:': 'docs',
    '重构：': 'refactor', 'refactor:': 'refactor',
    '安全：': 'security', 'security:': 'security',
    '测试：': 'test',     'test:': 'test',
  };

  // Detect prefix if --type not explicitly set
  if (!taskType) {
    for (const [prefix, type] of Object.entries(PREFIX_MAP)) {
      if (taskDesc.startsWith(prefix)) {
        taskType = type;
        break;
      }
    }
  }

  // If no prefix match, try content-based keyword detection
  if (!taskType) {
    const CONTENT_KEYWORDS = {
      bugfix: ['修复', 'bug', 'fix', '错误', '报错', 'crash', '崩溃', '失败', '不行', '不能用', '缺失', '丢了'],
      feature: ['新增', '添加', '优化', '改进', '实现', '开发', '创建', 'add', 'new', 'create', 'feature', '增加', '支持'],
      style:  ['样式', 'UI', '颜色', '字体', '布局', '调整', '美化', 'style', 'color', 'font', 'layout', '对齐'],
      audit: ['审计', '审查', '盘点', 'audit', 'review', '体检'],
      research: ['研究', '调研', '评估', '分析', 'research', '探索', '方案'],
      docs: ['文档', '说明', 'docs', 'documentation', 'doc', '手册'],
      refactor: ['重构', '清理', '整理', 'refactor', 'rename', '删除'],
      security: ['安全', '漏洞', '注入', 'security', 'vuln', '密钥'],
      test: ['测试', 'test', 'spec', '用例', 'coverage'],
    };

    const lower = taskDesc.toLowerCase();
    for (const [type, keywords] of Object.entries(CONTENT_KEYWORDS)) {
      if (keywords.some(kw => lower.includes(kw))) {
        taskType = type;
        break;
      }
    }
  }

  // Still no type? Reject with guidance
  if (!taskType) {
    console.log(`\n❌ 无法识别任务类型。请在任务描述前添加前缀：\n`);
    console.log(`   修复：<描述>    → 修复 bug`);
    console.log(`   优化：<描述>    → 功能优化 / 改进`);
    console.log(`   新增：<描述>    → 新功能`);
    console.log(`   样式：<描述>    → 样式调整`);
    console.log(`   需求：<描述>    → 泛需求描述`);
    console.log(`   审计：<描述>    → 审计 / 盘点`);
    console.log(`   研究：<描述>    → 研究 / 调研 / 评估`);
    console.log(`   文档：<描述>    → 文档类`);
    console.log(`   重构：<描述>    → 重构 / 清理`);
    console.log(`   安全：<描述>    → 安全相关`);
    console.log(`   测试：<描述>    → 测试相关\n`);
    console.log(`   或手动指定：harness gate --task "<描述>" --type feature|bugfix|style|audit|research|docs|refactor|security|test`);
    process.exit(1);
  }

  const detectedVia = getArg(args, '--type') ? '--type flag' :
    PREFIX_MAP[Object.keys(PREFIX_MAP).find(p => taskDesc.startsWith(p))] ? '前缀' : '内容关键词';
  console.log(`\n   ↳ 识别方式: ${detectedVia} → 任务类型: ${taskType}`);
  const gateDir = resolve(ROOT, 'harness', 'gates');
  mkdirSync(gateDir, { recursive: true });

  const now = new Date();
  const ts = now.toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const gateId = `GATE-${ts}`;
  const gateFile = join(gateDir, `${gateId}.json`);

  const searchChecks = [
    { id: 'search-backend-app',      label: 'Cross-layer: Search backend/app/' },
    { id: 'search-core',             label: 'Cross-layer: Search pallastrade_gems/pallastrade_core/' },
    { id: 'search-api',              label: 'Cross-layer: Search pallastrade_gems/pallastrade_api/' },
    { id: 'search-admin',            label: 'Cross-layer: Search pallastrade_gems/pallastrade_admin/' },
    { id: 'search-storefront',       label: 'Cross-layer: Search storefront/src/' },
    { id: 'search-platform',         label: 'Cross-layer: Search platform/packages/' },
  ];
  const verifyCheck = { id: 'verify-test', label: 'Verify: screenshot/log/DB — see TR-006 (no-test-needed only for docs)' };

  const checkDefs = {
    feature: [
      ...searchChecks,
      { id: 'read-skill-customization',label: 'Read Skill: pallastrade-customization/SKILL.md (always)' },
      { id: 'read-skill-domain',       label: 'Read Skill: domain-specific SKILL.md(s)' },
      { id: 'create-req-doc',          label: 'Create requirements doc: harness/requirements/REQ-*.md' },
      { id: 'req-doc-has-skill-table', label: 'REQ doc includes Skill consultation evidence table' },
      { id: 'user-confirmed',          label: 'User confirmed requirements doc (WAIT — do not proceed)' },
      verifyCheck,
    ],
    bugfix: [
      ...searchChecks,
      { id: 'read-skill-domain',       label: 'Read Skill: domain-specific SKILL.md(s)' },
      verifyCheck,
    ],
    style: [
      ...searchChecks,
      verifyCheck,
    ],
    audit: [
      ...searchChecks,
      { id: 'read-skill-domain',       label: 'Read Skill: domain-specific SKILL.md(s)' },
      verifyCheck,
    ],
    research: [
      ...searchChecks,
      { id: 'read-skill-domain',       label: 'Read Skill: domain-specific SKILL.md(s)' },
      verifyCheck,
    ],
    docs: [
      ...searchChecks,
      verifyCheck,
    ],
    refactor: [
      ...searchChecks,
      verifyCheck,
    ],
    security: [
      ...searchChecks,
      { id: 'read-skill-security',     label: 'Read Skill: pallastrade-security/SKILL.md' },
      verifyCheck,
    ],
    test: [
      ...searchChecks,
      verifyCheck,
    ],
  };

  const checks = checkDefs[taskType] || checkDefs.feature;

  let branch = 'unknown';
  let head = 'unknown';
  try {
    branch = execSync('git rev-parse --abbrev-ref HEAD', { cwd: ROOT, encoding: 'utf-8' }).trim();
    head = execSync('git rev-parse HEAD', { cwd: ROOT, encoding: 'utf-8' }).trim();
  } catch { /* not a git repo */ }

  const gateState = {
    id: gateId,
    taskType,
    taskDescription: taskDesc,
    createdAt: now.toISOString(),
    branch,
    head: head.slice(0, 8),
    checks: checks.map(c => ({ ...c, status: 'pending', completedAt: null })),
    cleared: false,
  };

  writeFileSync(gateFile, JSON.stringify(gateState, null, 2));

  console.log(`\n🔒 PRE-CODING GATE — ${gateId}`);
  console.log(`   Task: ${taskDesc}`);
  console.log(`   Type: ${taskType}`);
  console.log(`   Branch: ${branch} @ ${head.slice(0, 8)}`);
  console.log(`\n   You MUST clear all checks below before writing ANY code.\n`);
  for (const c of checks) {
    console.log(`   [ ] ${c.id}`);
    console.log(`       ${c.label}`);
  }
  console.log(`\n   To mark a check as done:`);
  console.log(`   harness gate:clear --gate ${gateId} --clear <check-id>`);
  console.log(`\n   Gate state saved to: harness/gates/${gateId}.json`);
  console.log(`\n❌ GATE NOT CLEARED — AI MUST NOT write or edit any files.`);

  process.exit(1);
}

// ================================================================
// gate:status — check active gate state (for continuation turns)
// ================================================================
else if (cmd === 'gate:status') {
  const { readdirSync } = await import('node:fs');
  const gateDir = resolve(ROOT, 'harness', 'gates');
  if (!existsSync(gateDir)) {
    console.log('No gates directory. Run `harness gate` to create one.');
    process.exit(1);
  }

  const files = readdirSync(gateDir)
    .filter(f => f.endsWith('.json'))
    .sort()
    .reverse();

  if (files.length === 0) {
    console.log('No active gates. Run `harness gate` to create one.');
    process.exit(1);
  }

  const latestFile = join(gateDir, files[0]);
  const gateState = JSON.parse(readFileSync(latestFile, 'utf-8'));
  const elapsed = Date.now() - new Date(gateState.createdAt).getTime();
  const hoursAgo = Math.round(elapsed / 3600000);

  // Differentiated expiry: feature 48h, bugfix 24h, style 8h
  const EXPIRY_HOURS = { feature: 48, bugfix: 24, style: 8 };
  const maxAge = EXPIRY_HOURS[gateState.taskType] || 24;

  console.log(`\n📋 Active Gate: ${gateState.id}`);
  console.log(`   Task: ${gateState.taskDescription}`);
  console.log(`   Type: ${gateState.taskType}`);
  console.log(`   Branch: ${gateState.branch} @ ${gateState.head}`);
  console.log(`   Created: ${hoursAgo}h ago (expires after ${maxAge}h)`);

  if (gateState.cleared) {
    const implementedCount = gateState.implemented?.length || 0;
    console.log(`   Status: ✅ CLEARED (${implementedCount} previous implementation(s))`);

    if (hoursAgo > maxAge) {
      console.log(`\n   ⚠️ Gate is ${hoursAgo}h old (max ${maxAge}h) — create a fresh gate.`);
      process.exit(1);
    }

    if (gateState.implemented && gateState.implemented.length > 0) {
      console.log(`\n   Previously implemented:`);
      gateState.implemented.forEach((impl, i) => {
        console.log(`     ${i + 1}. ${impl.what} (${impl.when})`);
      });
    }

    console.log(`\n   ✅ Gate valid. Continue implementation.`);
    process.exit(0);
  } else {
    const remaining = gateState.checks.filter(c => c.status !== 'done');
    console.log(`   Status: ❌ NOT CLEARED (${remaining.length} checks remaining)`);
    console.log(`   Remaining: ${remaining.map(c => c.id).join(', ')}`);
    process.exit(1);
  }
}

// ================================================================
// gate:clear — mark a gate check as done
// ================================================================
else if (cmd === 'gate:clear') {
  const gateId = getArg(args, '--gate');
  const checkId = getArg(args, '--clear');
  if (!gateId || !checkId) {
    console.log('Usage: harness gate:clear --gate <GATE-ID> --clear <check-id>');
    process.exit(1);
  }

  const gateFile = resolve(ROOT, 'harness', 'gates', `${gateId}.json`);
  if (!existsSync(gateFile)) {
    console.log(`Gate file not found: harness/gates/${gateId}.json`);
    process.exit(1);
  }

  const gateState = JSON.parse(readFileSync(gateFile, 'utf-8'));
  const check = gateState.checks.find(c => c.id === checkId);
  if (!check) {
    console.log(`Unknown check: ${checkId}`);
    console.log(`Available: ${gateState.checks.map(c => c.id).join(', ')}`);
    process.exit(1);
  }

  check.status = 'done';
  check.completedAt = new Date().toISOString();
  const note = getArg(args, '--note');
  if (note) check.note = note;

  const remaining = gateState.checks.filter(c => c.status !== 'done');
  gateState.cleared = remaining.length === 0;

  writeFileSync(gateFile, JSON.stringify(gateState, null, 2));

  console.log(`✅ ${checkId}: ${check.label}`);
  console.log(`   ${gateState.checks.filter(c => c.status === 'done').length}/${gateState.checks.length} checks cleared`);

  if (gateState.cleared) {
    console.log(`\n✅ GATE CLEARED — AI may now proceed with implementation.`);
    process.exit(0);
  } else {
    console.log(`\n❌ ${remaining.length} checks remaining. AI MUST NOT write or edit any files.`);
    console.log(`   Remaining: ${remaining.map(c => c.id).join(', ')}`);
    process.exit(1);
  }
}

// ================================================================
// gate:clean — remove expired/cleared gates older than N days
// ================================================================
else if (cmd === 'gate:clean') {
  const days = parseInt(getArg(args, '--days') || '7', 10);
  const gateDir = resolve(ROOT, 'harness', 'gates');
  if (!existsSync(gateDir)) { console.log('No gates directory.'); process.exit(0); }

  const files = readdirSync(gateDir).filter(f => f.endsWith('.json'));
  const cutoff = Date.now() - days * 86400000;
  let removed = 0;

  for (const file of files) {
    const filePath = join(gateDir, file);
    const gate = JSON.parse(readFileSync(filePath, 'utf-8'));
    const age = Date.now() - new Date(gate.createdAt).getTime();
    if (gate.cleared && age > cutoff) {
      unlinkSync(filePath);
      removed++;
      console.log(`🗑  Removed: ${file} (${Math.round(age / 3600000)}h old, cleared)`);
    }
  }

  console.log(`\n✅ gate:clean — removed ${removed} gate(s) older than ${days} day(s).`);
  console.log(`   ${files.length - removed} gate(s) retained.`);
}

// ================================================================
// help
// ================================================================
else {
  console.log(`PallasTrade Harness CLI

Usage: node scripts/harness/cli.mjs <command> [options]

Gate (MANDATORY before coding):
  gate --task "description" [--type feature|bugfix|style]
                                      Create pre-coding gate. AI MUST clear
                                      all checks before writing any code.
  gate:status                         Check if an active gate exists (for
                                      continuation turns on same task).
  gate:clear --gate <ID> --clear <id> Mark a gate check as completed.

Environment:
  doctor [--fix-safe] [--format json]   Diagnose local dev environment

Analysis:
  affected --base origin/main           Show affected components

Quality:
  check --profile quick|full|release    Run quality gates
  e2e dashboard|storefront              Run end-to-end tests
  eval-ai --check-freshness             Verify skill path validity
  eval-ai --scenarios                   Validate GS scenario library
  generated:check                       Check generated files for drift
  doc-impact --base origin/main         Check knowledge docs are synced

Evidence:
  evidence collect                      Collect structured delivery evidence
  diagnostics collect                   Collect failure diagnostics
`);
}

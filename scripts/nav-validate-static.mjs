#!/usr/bin/env node
// PALLAS-CUSTOM: 管理后台导航 Schema 静态校验（P5）
// 纯 Node，无 Rails 依赖 —— 供 lefthook pre-commit 与 harness nav-validate 插件降级使用。
// 权威校验器：bin/rails pallastrade:admin:nav_validate（runtime 结构 + 源码检测）
// 本脚本只做静态扫描：子项 `if:` 业务关键字 + 顶级 icon 缺失。
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const NAV_CONFIG = 'backend/pallastrade_gems/pallastrade_admin/config/initializers/pallastrade_admin_navigation.rb';

// 业务关键字黑名单（出现在 if: -> 即视为用业务状态隐藏菜单）
const BUSINESS = /\b(count|size|state|status|positive\?|present\?|supported_locales|ready_to_ship|empty\?)\b/;
// getting_started 豁免（决策 2：wizard 完成后隐藏）
const GETTING_STARTED = /getting_started|setup_completed/;

export function scanNavConfig(rootDir) {
  const file = resolve(rootDir, NAV_CONFIG);
  if (!existsSync(file)) return { pass: true, violations: [], note: 'nav config not found — skipped' };

  const lines = readFileSync(file, 'utf-8').split('\n');
  const violations = [];
  let currentTopKey = null;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    // 追踪顶级项（sidebar_nav.add / settings_nav.add :key,）
    const topAdd = line.match(/(?:sidebar_nav|settings_nav)\.add\s+:(\w+)/);
    if (topAdd) currentTopKey = topAdd[1];

    // 子项/顶级 if: 业务条件检测（单行 lambda）
    if (line.includes('if:') && line.includes('->')) {
      const context = lines.slice(Math.max(0, i - 3), i + 1).join('\n');
      // 只检查 add 块内的 if:（排除 badge/tooltip 等）
      if (BUSINESS.test(line)) {
        // 豁免 getting_started
        if (GETTING_STARTED.test(context) && currentTopKey === 'getting_started') continue;
        violations.push(`${NAV_CONFIG}:${i + 1}  if: 含业务状态关键字（${line.trim().slice(0, 90)}...）— 业务计数须用 badge`);
      }
    }
  }

  return {
    pass: violations.length === 0,
    violations,
    note: violations.length ? undefined : 'static scan OK',
  };
}

// CLI：node scripts/nav-validate-static.mjs [rootDir]
import { fileURLToPath } from 'node:url';

const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const rootDir = process.argv[2] || process.cwd();
  const result = scanNavConfig(rootDir);
  if (result.pass) {
    console.log(`✅ nav:validate (static) OK — ${result.note || ''}`);
    process.exit(0);
  } else {
    console.log(`❌ nav:validate (static) — ${result.violations.length} violation(s):`);
    result.violations.forEach((v) => console.log(`   🚫 ${v}`));
    process.exit(1);
  }
}

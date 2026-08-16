// PALLAS-CUSTOM: 管理后台导航 Schema 校验插件（P5 导航架构重构）
// 注册 `nav-validate` check（纳入 `harness check --profile quick`）。
// 1. 优先运行权威 Rails 校验器（docker exec pallastrade-web-1 bin/rails pallastrade:admin:nav_validate）
// 2. docker/Rails 不可用（如 pre-commit 无容器）→ 降级为纯 Node 静态扫描
//    （业务 if: 关键字 + getting_started 豁免，与 scripts/nav-validate-static.mjs 同逻辑）
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
import { scanNavConfig } from '../../scripts/nav-validate-static.mjs';

export const manifest = {
  name: 'pallastrade-nav-validate',
  apiVersion: '1.0',
  capabilities: ['checks'],
};

const NAV_CONFIG = 'backend/pallastrade_gems/pallastrade_admin/config/initializers/pallastrade_admin_navigation.rb';

function dockerAvailable() {
  try {
    execFileSync('docker', ['ps', '--format', '{{.Names}}'], {
      encoding: 'utf-8',
      stdio: ['ignore', 'pipe', 'ignore'],
      timeout: 5000,
    });
    return true;
  } catch {
    return false;
  }
}

export const checks = [
  {
    id: 'nav-validate',
    label: 'Admin navigation schema validation (P5)',
    run: ({ rootDir }) => {
      // ① 权威校验：Rails rake task（docker）
      if (dockerAvailable()) {
        try {
          const out = execFileSync(
            'docker',
            ['exec', '-e', 'DISABLE_SIMPLECOV_MINIMUM=1', 'pallastrade-web-1', 'bin/rails', 'pallastrade:admin:nav_validate'],
            { encoding: 'utf-8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 120000 },
          );
          const last = out.trim().split('\n').filter(Boolean).pop() || 'passed';
          return { message: `Rails: ${last}` };
        } catch (e) {
          const out = String(e.stdout || '');
          if (/nav:validate OK/.test(out)) {
            return { message: `Rails: ${out.trim().split('\n').filter(Boolean).pop()}` };
          }
          // docker 可用但 rake 失败（违规）→ 阻断；无法确定时给静态扫描结论
          const violations = out.trim().split('\n').filter((l) => l.includes('🚫'));
          if (violations.length) {
            return { pass: false, message: `${violations.length} violation(s): ${violations.slice(0, 3).join(' | ')}` };
          }
        }
      }

      // ② 降级：纯 Node 静态扫描（无 Rails 依赖）
      const result = scanNavConfig(rootDir);
      if (!result.pass) {
        return { pass: false, message: `${result.violations.length} violation(s): ${result.violations.slice(0, 3).join(' | ')}` };
      }
      return { message: `static: ${result.note || 'OK'} (Rails unavailable)` };
    },
  },
];

export const scanners = [
  {
    id: 'nav-validate',
    label: 'Admin navigation schema validation (static)',
    glob: '**/pallastrade_admin_navigation.rb',
    run: ({ rootDir }) => {
      const result = scanNavConfig(rootDir);
      return result.pass ? [] : result.violations.map((v) => ({ severity: 'error', message: v }));
    },
  },
];

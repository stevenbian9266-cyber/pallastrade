// PRD-20260913 边界收口 / P0：pull-deploy 前滚检测缺陷回归守卫
//
// 背景（rollback drill 实测，见 docs/operations/runbooks/ROLLBACK-DRILL-dev.md §4.2）：
//   旧版 `pull-deploy.sh` 只比对**状态文件**里的 (head, storefront digest)。手动回滚或
//   构建半途失败后状态文件不变 → 被判定「无变化」→ 静默长期运行旧版本，而状态文件看起来是绿的。
//
// 修复：状态文件降级为"优化"，事实来源改为**实际运行态** ——
//   后端：镜像内版本戳 `/rails/.deployed-revision`（deploy.sh 构建前写入构建上下文 → COPY 烘进镜像）
//   storefront：运行容器的镜像 ID
//   任一对不上 → 强制部署（前滚保证）。
//
// 本文件是**契约/顺序守卫**：断言两个脚本的关键接线存在且顺序正确（bash 逻辑的行为测试由
// 服务器上的真实一轮 pull-deploy 提供证据）。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const pullDeploy = readFileSync(join(repoRoot, 'deploy', 'pull-deploy.sh'), 'utf8');
const deploySh = readFileSync(join(repoRoot, 'deploy', 'deploy.sh'), 'utf8');
const dockerignore = readFileSync(join(repoRoot, 'backend', '.dockerignore'), 'utf8');
const gitignore = readFileSync(join(repoRoot, '.gitignore'), 'utf8');

const STAMP = '.deployed-revision';

test('PD-01 pull-deploy 读取运行中容器的版本戳（实际运行态）', () => {
  assert.match(pullDeploy, /docker exec "\$WEB_CONTAINER" cat \/rails\/\.deployed-revision/);
  assert.match(pullDeploy, /WEB_CONTAINER="pallastrade-dev-web-1"/);
});

test('PD-02 pull-deploy 读取 storefront 运行容器的镜像 ID', () => {
  assert.match(pullDeploy, /docker inspect --format '\{\{\.Image\}\}' "\$SF_CONTAINER"/);
  assert.match(pullDeploy, /SF_CONTAINER="pallastrade-dev-storefront-1"/);
});

test('PD-03 运行态 ≠ 期望 → 强制部署（前滚保证）', () => {
  assert.match(pullDeploy, /if \[ "\$RUNNING_HEAD" != "\$NEW_HEAD" \]; then\s*\n\s*add_reason/);
  assert.match(pullDeploy, /storefront 运行镜像陈旧/);
});

test('PD-04 跳过分支只在无任何部署理由时成立', () => {
  const skipIdx = pullDeploy.lastIndexOf('无变化');
  assert.ok(skipIdx > 0, '缺少"无变化"分支');
  const guard = pullDeploy.slice(Math.max(0, skipIdx - 200), skipIdx);
  assert.match(guard, /if \[ -z "\$DEPLOY_REASON" \]; then/);
});

test('PD-05 状态文件仅作为"变化"输入之一，不再单独决定跳过', () => {
  // 旧缺陷形态：`[ "$NEW_HEAD" = "$OLD_HEAD" ] && [ "$NEW_IMG_ID" = "$OLD_IMG_ID" ]` 直接 exit 0
  assert.doesNotMatch(pullDeploy, /if \[ "\$NEW_HEAD" = "\$OLD_HEAD" \] && \[ "\$NEW_IMG_ID" = "\$OLD_IMG_ID" \]; then/);
});

test('PD-06 pull-deploy 把目标 revision 传给 deploy.sh（避免二次推断）', () => {
  assert.match(pullDeploy, /DEPLOY_REVISION="\$NEW_HEAD" bash deploy\/deploy\.sh/);
});

test('PD-07 deploy.sh 在构建前写版本戳（顺序：先写戳，后 build）', () => {
  const stampIdx = deploySh.indexOf(`> ../backend/${STAMP}`);
  const buildIdx = deploySh.indexOf('build web worker');
  assert.ok(stampIdx > 0, 'deploy.sh 未写版本戳');
  assert.ok(buildIdx > stampIdx, '版本戳必须写在 docker compose build 之前');
  assert.match(deploySh, /REVISION="\$\{DEPLOY_REVISION:-\$\(git rev-parse HEAD/);
});

test('PD-08 版本戳不会被 dockerignore 排除（否则镜像里读不到）', () => {
  const lines = dockerignore.split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
  const excludes = lines.some((pattern) => {
    if (pattern === STAMP) return true;
    if (pattern === '.*' || pattern === './') return true;
    return pattern.endsWith('*') && STAMP.startsWith(pattern.slice(0, -1));
  });
  assert.equal(excludes, false, '.deployed-revision 会被 .dockerignore 排除，镜像内将读不到版本戳');
});

test('PD-09 版本戳是本地运行产物，不进版本库', () => {
  assert.match(gitignore, /^\.deployed-revision$/m);
});

test('PD-10 脚本仍是 bash 严格模式且 dev-only 守卫保留', () => {
  for (const script of [pullDeploy, deploySh]) {
    assert.match(script, /set -euo pipefail/);
  }
  assert.match(pullDeploy, /if \[ "\$ENV" != "dev" \]; then/);
  assert.match(deploySh, /if \[ "\$ENV" != "dev" \]; then/);
});

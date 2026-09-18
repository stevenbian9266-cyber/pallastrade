// 部署路径过滤守卫
// PRD-20260918-infra-dev-deploy-storefront-image-path-filter AC-001 AC-002 AC-003 AC-004
//
// 背景（2026-09-18，TASK-20260918074058-bafcc3c9）：
//   `deploy.yml` 原先对 dev 的**每次 push** 都重建并推送 storefront 镜像（无 paths 过滤）。
//   构建产物随源码 mtime 变化 → 即便 storefront 一个字节未改，也会产出新的 manifest digest。
//   服务器 `deploy/pull-deploy.sh` 每轮都要先执行一次跨境拉取（预算 900s；实测是**真实下载**
//   而不是空转：镜像收敛后同一命令在四种上下文下均 1–2s 返回），于是**与 storefront 无关的
//   后端部署被推迟最多 15 分钟**，其间每 5 分钟的 cron tick 都被 flock 跳过。
//
// 因此这里守两件事：
//   1. 过滤集合必须覆盖 `storefront/Dockerfile` 的**每一个 COPY 来源** —— 新增来源却忘记同步
//      `paths` 时，本测试失败（否则优化会静默挡住 storefront 变更的构建）；
//   2. 手工强制重建的入口（`workflow_dispatch`）与分支范围（`[dev]`）不得被顺手删掉。
//
// 跑法（仓库根；Rails 容器只挂载 backend/，故放在 node:test 侧）：
//   node --test tests/deploy-paths-filter.test.mjs   （或 harness verify repo-guards-test）
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = (relativePath) => readFileSync(join(repoRoot, relativePath), 'utf8');

const workflow = read('.github/workflows/deploy.yml');
const dockerfile = read('storefront/Dockerfile');

const WORKFLOW_PATH = '.github/workflows/deploy.yml';

/** 抽出 YAML 里某个键（默认 `paths`）下的列表项；按缩进判定块范围，不需要 YAML 依赖。 */
export function extractList(yaml, key = 'paths') {
  const lines = yaml.split(/\r?\n/);
  const anchor = lines.findIndex((line) => new RegExp(`^\\s+${key}:\\s*$`).test(line));
  if (anchor === -1) return null;

  const anchorIndent = lines[anchor].match(/^\s*/)[0].length;
  const items = [];

  for (let i = anchor + 1; i < lines.length; i += 1) {
    const line = lines[i];
    if (!line.trim()) continue;

    const indent = line.match(/^\s*/)[0].length;
    if (indent <= anchorIndent) break;

    const match = line.match(/^\s*-\s*'?([^'\s]+)'?\s*$/);
    if (match) items.push(match[1]);
  }

  return items;
}

/** Dockerfile 里来自**仓库**的 COPY 来源（排除 `--from=<stage>` 的阶段拷贝与各类 flag）。 */
export function copySources(dockerfileText) {
  const sources = new Set();

  for (const raw of dockerfileText.split(/\r?\n/)) {
    const line = raw.trim();
    if (!/^COPY\s/i.test(line)) continue;
    if (/--from=/.test(line)) continue;

    const tokens = line
      .split(/\s+/)
      .slice(1)
      .filter((token) => !token.startsWith('--'));

    // 最后一个 token 是目标路径，其余是来源
    if (tokens.length < 2) continue;
    for (const src of tokens.slice(0, -1)) {
      sources.add(src.replace(/\/+$/, ''));
    }
  }

  return [...sources];
}

const normalize = (value) => value.replace(/^\.\//, '').replace(/\/+$/, '');

/** 单个来源是否被 glob 集合覆盖（支持 `dir/**` 与精确路径两种写法）。 */
export function isCovered(source, globs) {
  const target = normalize(source);

  return globs.some((glob) => {
    const pattern = normalize(glob);
    if (!pattern.endsWith('/**')) return target === pattern;

    const base = pattern.slice(0, -3);
    return target === base || target.startsWith(`${base}/`);
  });
}

const pushPaths = extractList(workflow);
const sources = copySources(dockerfile);

test('DEPLOY-PATHS-01 on.push 存在非空 paths 过滤（AC-001）', () => {
  assert.ok(Array.isArray(pushPaths), 'deploy.yml 的 on.push 缺少 paths —— 每次 push 都会重建镜像');
  assert.ok(pushPaths.length > 0, 'deploy.yml 的 paths 过滤为空 —— 等同没有过滤');
});

test('DEPLOY-PATHS-02 Dockerfile 的每个 COPY 来源都被 paths 覆盖（AC-002）', () => {
  assert.ok(sources.length >= 2, `Dockerfile COPY 来源解析异常（只解析到 ${sources.length} 个）`);

  const uncovered = sources.filter((src) => !isCovered(src, pushPaths));
  assert.deepEqual(
    uncovered,
    [],
    `以下构建来源未被 deploy.yml 的 paths 覆盖，storefront 变更将不会触发镜像重建：${uncovered.join(', ')}`,
  );
});

test('DEPLOY-PATHS-03 保留 workflow_dispatch 与 branches [dev]（AC-003）', () => {
  assert.match(workflow, /^  workflow_dispatch:/m, '缺少 workflow_dispatch —— 无法手工强制重建镜像');
  assert.match(workflow, /^\s{4}branches:\s*\[dev\]/m, 'Deploy 应仍只监听 dev 分支');
});

test('DEPLOY-PATHS-04 覆盖判定本身有效（AC-004，反例自证）', () => {
  assert.equal(isCovered('storefront/', pushPaths), true);
  assert.equal(isCovered('platform/packages/sdk/dist/index.d.ts', pushPaths), true);
  assert.equal(
    isCovered('backend/app/models/pallastrade/product.rb', pushPaths),
    false,
    '后端路径不应触发镜像重建（这正是本优化的收益点）',
  );
  assert.equal(
    isCovered('platform/packages/dashboard/src/index.ts', pushPaths),
    false,
    '未被 COPY 的包不应触发重建；若 Dockerfile 新增了该来源，DEPLOY-PATHS-02 会立刻报出',
  );
  assert.equal(isCovered('.github/workflows/deploy.yml', pushPaths), true);
  assert.equal(WORKFLOW_PATH, '.github/workflows/deploy.yml');
});

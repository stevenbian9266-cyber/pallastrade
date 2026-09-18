// AI 部署模板契约守卫（PRD-20260918-api-deepseek-structured-output AC-012）
//
// 背景（2026-09-18 dev 事故，TASK-20260918020017-217247b3）：
//   AI 可用性由 8 道闸门串行把关，第一道是系统级总开关 `PALLASTRADE_AI_ENABLED`（默认 false）。
//   该变量**没有出现在任何一个 .env.example 里** —— 服务器模板 `deploy/.env.dev.example`
//   与 `backend/.env.example` 都没有。于是按模板新建 / 重建的环境会静默地「AI 永远不可用」：
//   四个能力一律只报笼统的 `ai_disabled`，不提示缺哪一层，排查代价极高。
//   同理 `ACTIVE_RECORD_ENCRYPTION_*`（AI 供应商密钥与 Gateway preferences 等加密列的前提）
//   也未在服务器模板登记，缺失时 encrypts 惰性退化为明文 / ProviderSecret fail-closed。
//
// 因此这些断言是**部署模板契约**：模板必须让新环境能一次配对，且绝不允许内置真实密钥。
// 跑在仓库根（Rails 容器只挂载 backend/，仓库根在容器内不可达，故放在 node:test 侧）：
//   node --test tests/ai-env-template.test.mjs   （或 harness verify repo-guards-test）
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = (relativePath) => readFileSync(join(repoRoot, relativePath), 'utf8');

const serverTemplate = read('deploy/.env.dev.example');
const backendTemplate = read('backend/.env.example');

/** 只保留生效行（模板里大量变量是注释形式的说明，不能当作已登记）。 */
const activeLines = (text) =>
  text
    .split(/\r?\n/)
    .filter((line) => !/^\s*#/.test(line));

test('AI-ENV-01 服务器模板登记 AI 系统总开关（生效行，非注释）', () => {
  assert.match(
    serverTemplate,
    /^PALLASTRADE_AI_ENABLED=/m,
    'deploy/.env.dev.example 缺少生效的 PALLASTRADE_AI_ENABLED —— 新环境会静默 AI 不可用',
  );
});

test('AI-ENV-02 后端模板登记 AI 系统总开关（注释引导可接受）', () => {
  assert.match(
    backendTemplate,
    /^#?\s*PALLASTRADE_AI_ENABLED=/m,
    'backend/.env.example 缺少 PALLASTRADE_AI_ENABLED 说明',
  );
});

test('AI-ENV-03 服务器模板登记三个 Active Record Encryption 密钥', () => {
  for (const key of ['PRIMARY_KEY', 'DETERMINISTIC_KEY', 'KEY_DERIVATION_SALT']) {
    assert.match(
      serverTemplate,
      new RegExp(`ACTIVE_RECORD_ENCRYPTION_${key}=`),
      `deploy/.env.dev.example 缺少 ACTIVE_RECORD_ENCRYPTION_${key}`,
    );
  }
});

test('AI-ENV-04 服务器模板不得内置真实密钥值', () => {
  const offenders = activeLines(serverTemplate).filter((line) =>
    /^[A-Z_]*(KEY|SECRET|TOKEN|PASSWORD)[A-Z_]*=\S+/.test(line),
  );

  assert.deepEqual(
    offenders,
    [],
    `以下行疑似内置真实密钥（模板只允许留空或占位）：\n${offenders.join('\n')}`,
  );
});

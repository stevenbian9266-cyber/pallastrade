// AI 助手接线契约守卫（PRD-20260918-admin-ai-output-validation FR-004）
//
// 背景（2026-09-18 实测，任务 TASK-20260918025044-fc936a9e）：
//   后台 5 处 AI 助手容器把属性哈希直接交给 `tag.attributes`，键名没有 `data-` 前缀，
//   渲染出的是 `controller="ai-assist"` / `ai_assist_endpoint_value="…"` 这样的**普通属性**。
//   后果不是"样式不对"，而是整块功能在浏览器里是死的：
//     * Stimulus 只认 `data-controller` → 控制器从未挂载 → `data-action="click->…"` 永不派发
//       （按钮点了没反应）；渲染断言 `[data-controller~="ai-assist"]` 为空即为证据；
//     * `data-ai-assist-*-value` 同理缺失；
//     * 文案键要经 dataset 的驼峰换算，`Error:<code>` 这类名字根本活不过那一趟编码。
//
//   任何只看 ERB、或只看 JS 的评审都会放行 —— 所以契约要放在两边之间断言。
//   渲染层由 `spec/requests/pallastrade/admin/ai_assist_wiring_spec.rb` 断言商品页与
//   catalog_health；本文件覆盖另外三处视图（它们需要更重的数据前置才能渲染），
//   以及控制器必须保留的兜底分支。
//
// 说明：这是**静态契约守卫**（断言源码接线），不是行为测试。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = (relativePath) => readFileSync(join(repoRoot, relativePath), 'utf8');

const ADMIN = 'backend/pallastrade_gems/pallastrade_admin';

const ASSISTANT_VIEWS = [
  'app/views/pallastrade/admin/shared/_seo.html.erb',
  'app/views/pallastrade/admin/products/form/_base.html.erb',
  'app/views/pallastrade/admin/translations/products/_form.html.erb',
  'app/views/pallastrade/admin/catalog_health/index.html.erb',
  'app/views/pallastrade/admin/catalog_health/_product_card.html.erb',
];

test('AI-ASSIST-01 每处助手容器都经共享 helper 接线（data: 前缀 + 文案 JSON）', () => {
  for (const view of ASSISTANT_VIEWS) {
    const source = read(join(ADMIN, view));

    assert.match(
      source,
      /ai_assist_attributes\(/,
      `${view} 未走 ai_assist_attributes —— 裸属性名不会变成 data-*，Stimulus 不会挂载`,
    );
  }
});

test('AI-ASSIST-02 不得再出现没有 data: 前缀的 controller: 哈希', () => {
  for (const view of ASSISTANT_VIEWS) {
    const source = read(join(ADMIN, view));

    assert.doesNotMatch(
      source,
      /controller:\s*'ai-assist'/,
      `${view} 仍有裸 controller: 键（旧缺陷形态：渲染成 controller="ai-assist"）`,
    );
  }
});

test('AI-ASSIST-03 helper 把文案作为单一 JSON 属性下发', () => {
  const helper = read(join(ADMIN, 'app/helpers/pallastrade/admin/ai_assist_helper.rb'));

  assert.match(helper, /controller:\s*'ai-assist'/, 'helper 必须负责 data-controller');
  assert.match(helper, /ai_assist_labels:\s*ai_assist_labels\(/, 'helper 必须下发文案 JSON');
  assert.match(helper, /ErrorFallback/, 'helper 必须提供通用兜底文案键');
});

test('AI-ASSIST-04 控制器保留兜底分支且按 JSON 取文案', () => {
  const controller = read(join(ADMIN, 'app/javascript/pallastrade/admin/controllers/ai_assist_controller.js'));

  assert.match(
    controller,
    /this\.labels\[name\]/,
    '控制器应从 JSON 文案表取名，而不是按 dataset 驼峰键猜名字',
  );
  assert.match(
    controller,
    /this\.label\('ErrorFallback'\)/,
    '缺少兜底：未映射的错误码会渲染成空白状态，商家只看到「什么都没发生」',
  );
});

test('AI-ASSIST-05 三个新错误码在两种语言里都有文案', () => {
  const en = read(join(ADMIN, 'config/locales/en.yml'));
  const zh = read('backend/config/locales/admin_products_ai.zh-CN.yml');

  for (const code of ['ai_output_invalid', 'ai_provider_unavailable', 'ai_credentials_invalid']) {
    assert.match(en, new RegExp(`^\\s+${code}:`, 'm'), `en 缺少 ${code}`);
    assert.match(zh, new RegExp(`^\\s+${code}:`, 'm'), `zh-CN 缺少 ${code}`);
  }
});

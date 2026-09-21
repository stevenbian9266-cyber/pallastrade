/**
 * PRD 模板结构守卫（v3 · 17 节契约）
 *
 * 关联 PRD：docs/prd/harness/PRD-20260921-harness-prd-template-v3.md
 * 覆盖：
 *   PRD-20260921-harness-prd-template-v3 AC-001 — 模板章节序列 §0–§16（17 节，无跳号无重复）
 *   PRD-20260921-harness-prd-template-v3 AC-002 — §3.2 功能详述八要件
 *   PRD-20260921-harness-prd-template-v3 AC-003 — §4 界面规格（UI）五子节 + 状态矩阵 / token / i18n 关键词
 *   PRD-20260921-harness-prd-template-v3 AC-004 — §5 交互与体验（UX）四子节 + 防重复 / 边界 / AP-009
 *   PRD-20260921-harness-prd-template-v3 AC-005 — §6 数据与埋点两子节 + 豁免写法 + 禁 PII
 *   PRD-20260921-harness-prd-template-v3 AC-006 — 写作要求（200/150/100 · 节级豁免 · 注释纪律 · 写码前必备节 · 无 phantom AC）
 *   PRD-20260921-harness-prd-template-v3 AC-007 — 本守卫已注册进 harness.config.mjs 的 repo-guards-test
 *   PRD-20260921-harness-prd-template-v3 AC-008 — SKILL / 场景库 / promptfoo 与模板同契约（17 节 + 新规则）
 *   PRD-20260921-harness-prd-template-v3 AC-009 — 元数据含「目标用户」「界面影响」
 *
 * 运行：node --test tests/prd-template-structure.test.mjs
 * 说明：仅读取仓库内文件（docs/prd/_TEMPLATE.md、ai/skills/pallastrade-prd/SKILL.md、
 *       harness/scenarios/scenarios.json、harness/promptfoo/prompts/gs-013.txt、
 *       harness.config.mjs），零依赖、零副作用。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (rel) => readFileSync(path.join(ROOT, rel), 'utf8');
const stripComments = (text) => text.replace(/<!--[\s\S]*?-->/g, '');

/** 截取 [startMarker, endMarker) 之间的文本（含 startMarker） */
function block(text, startMarker, endMarker) {
  const start = text.indexOf(startMarker);
  assert.notEqual(start, -1, `缺少起始标记：${startMarker}`);
  const end = text.indexOf(endMarker, start + startMarker.length);
  assert.notEqual(end, -1, `缺少结束标记：${endMarker}`);
  return text.slice(start, end);
}

const template = stripComments(read('docs/prd/_TEMPLATE.md'));
const templateRaw = read('docs/prd/_TEMPLATE.md');

test('模板章节序列 = §0–§16 共 17 节，无跳号无重复（AC-001）', () => {
  const sections = [...template.matchAll(/^## (\d+)\. /gm)].map((m) => Number(m[1]));
  const expected = Array.from({ length: 17 }, (_, i) => i);
  assert.deepEqual(
    sections,
    expected,
    `顶级章节序列应为 §0..§16；实际 [${sections.join(',')}]`,
  );
});

test('§3.2 功能详述含八要件（AC-002）', () => {
  const frBlock = block(template, '### 3.2 功能详述', '## 4. 界面规格（UI）');
  for (const key of [
    '触发与入口',
    '前置条件',
    '主流程',
    '分支与边界',
    '异常处理',
    '后置状态',
    '权限',
    '验收映射',
  ]) {
    assert.ok(frBlock.includes(key), `§3.2 缺少要件：${key}`);
  }
});

test('§4 界面规格（UI）五子节 + 状态矩阵 / token / i18n 关键词（AC-003）', () => {
  const ui = block(template, '## 4. 界面规格（UI）', '## 5. 交互与体验（UX）');
  for (const sub of [
    '### 4.1 页面与路由清单',
    '### 4.2 组件与复用决策',
    '### 4.3 页面状态矩阵',
    '### 4.4 视觉与设计 token',
    '### 4.5 文案与 i18n',
  ]) {
    assert.ok(ui.includes(sub), `§4 缺少子节：${sub}`);
  }
  for (const state of ['loading', 'empty', 'error', 'success', '禁用']) {
    assert.ok(ui.includes(state), `§4 状态矩阵缺少状态：${state}`);
  }
  assert.ok(ui.includes('AP-001') && ui.includes('AP-006'), '§4 缺少反模式引用 AP-001 / AP-006');
  assert.ok(ui.includes('locale key'), '§4 缺少 locale key 列');
});

test('§5 交互与体验（UX）四子节 + 防重复 / 边界 / AP-009（AC-004）', () => {
  const ux = block(template, '## 5. 交互与体验（UX）', '## 6. 数据与埋点');
  for (const sub of [
    '### 5.1 核心操作流程',
    '### 5.2 反馈机制',
    '### 5.3 边界与异常体验',
    '### 5.4 无障碍与键盘',
  ]) {
    assert.ok(ux.includes(sub), `§5 缺少子节：${sub}`);
  }
  assert.ok(ux.includes('防重复'), '§5 反馈机制缺少「防重复」');
  for (const edge of ['超时', '并发', '权限不足']) {
    assert.ok(ux.includes(edge), `§5 边界矩阵缺少场景：${edge}`);
  }
  assert.ok(ux.includes('AP-009'), '§5 缺少 AP-009 降级纪律引用');
});

test('§6 数据与埋点两子节 + 豁免写法 + 禁 PII（AC-005）', () => {
  const data = block(template, '## 6. 数据与埋点', '## 7. 非功能需求（NFR）');
  assert.ok(data.includes('### 6.1 指标口径'), '§6 缺少子节：6.1 指标口径');
  assert.ok(data.includes('### 6.2 事件清单'), '§6 缺少子节：6.2 事件清单');
  assert.ok(data.includes('不适用'), '§6 缺少「不适用 + 理由」豁免写法');
  assert.ok(data.includes('禁 PII'), '§6 事件清单缺少「禁 PII」约束');
  assert.ok(data.includes('不可判定'), '§6 指标口径缺少「不可判定」纪律');
});

test('写作要求：篇幅下限 200/150/100 + 节级豁免 + 注释纪律 + 写码前必备节 + 无 phantom AC（AC-006）', () => {
  const rules = block(template, '# PRD-{YYYYMMDD}-{category}-{slug}', '## 0. 摘要（TL;DR）');
  for (const floor of ['≥ 200 行', '≥ 150 行', '≥ 100 行']) {
    assert.ok(rules.includes(floor), `写作要求缺少篇幅下限：${floor}`);
  }
  for (const exemption of ['§6 数据与埋点', '§14 决策记录', '§15 开放问题']) {
    assert.ok(rules.includes(exemption), `写作要求豁免清单缺少：${exemption}`);
  }
  assert.ok(rules.includes('HTML 注释'), '写作要求缺少「示例放 HTML 注释」纪律');
  for (const preCode of ['§9 跨层搜索', '§13 风险与回滚', '§14 决策记录']) {
    assert.ok(rules.includes(preCode), `写作要求缺少「写码前必备节」：${preCode}`);
  }
  const phantom = [...template.matchAll(/AC-\d+/g)].map((m) => m[0]);
  assert.deepEqual(
    phantom,
    [],
    `模板非注释区不得出现真实形态的 AC 编号（phantom AC）：${phantom.join(', ')}`,
  );
  assert.ok(templateRaw.includes('<!--'), '模板应示范 HTML 注释用法（示例注释纪律）');
});

test('repo-guards-test 已注册本守卫（AC-007）', () => {
  const config = read('harness.config.mjs');
  assert.ok(
    config.includes("'tests/prd-template-structure.test.mjs'"),
    'harness.config.mjs 的 repo-guards-test 命令数组缺少 tests/prd-template-structure.test.mjs',
  );
});

test('SKILL / 场景库 / promptfoo 与模板同契约（AC-008）', () => {
  const skill = read('ai/skills/pallastrade-prd/SKILL.md');
  for (let i = 0; i <= 16; i += 1) {
    assert.ok(skill.includes(`§${i} `), `SKILL §2.3 清单缺少 §${i}`);
  }

  const scenarios = JSON.parse(read('harness/scenarios/scenarios.json'));
  const gs13 = scenarios.scenarios.find((s) => s.id === 'GS-013');
  assert.ok(gs13, 'scenarios.json 缺少 GS-013');
  assert.ok(gs13.description.includes('17 sections'), 'GS-013 description 未声明 17 sections');
  assert.ok(gs13.description.includes('§0–§16'), 'GS-013 description 未声明 §0–§16');
  assert.ok(
    gs13.mustDo.some((item) => item.includes('17 template sections')),
    'GS-013 mustDo 未要求填满 17 节',
  );
  assert.ok(
    gs13.mustDo.some((item) => item.includes('>= 200 lines') && item.includes('>= 150') && item.includes('>= 100')),
    'GS-013 mustDo 未声明 200/150/100 篇幅下限',
  );
  assert.ok(
    gs13.mustDo.some((item) => item.includes('§4 UI') && item.includes('§5 UX') && item.includes('§6')),
    'GS-013 mustDo 未包含 UI / UX / 数据与埋点节要求',
  );
  assert.ok(
    gs13.mustNotDo.some((item) => item.includes('不适用')),
    'GS-013 mustNotDo 未包含豁免写法约束',
  );

  const prompt = read('harness/promptfoo/prompts/gs-013.txt');
  assert.ok(prompt.includes('17 sections'), 'promptfoo gs-013.txt 未同步 17 节契约');
  assert.ok(prompt.includes('>= 200 lines'), 'promptfoo gs-013.txt 未同步篇幅下限');
  assert.ok(prompt.includes('不适用'), 'promptfoo gs-013.txt 未同步豁免写法');
});

test('元数据含「目标用户」「界面影响」行（AC-009）', () => {
  assert.ok(template.includes('| 目标用户 |'), '元数据表缺少「目标用户」行');
  assert.ok(template.includes('| 界面影响 |'), '元数据表缺少「界面影响」行');
});

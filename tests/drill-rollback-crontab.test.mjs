// 部署脚本回归守卫：drill-rollback 的 crontab 恢复（台账 TASK-20260913103421-bd645649 收口）
//
// 背景（2026-09-13 首次回滚演练实测，runbook `docs/operations/runbooks/ROLLBACK-DRILL-dev.md` §5）：
//   脚本原先用 `sed -i "$CRON_BAK"` + `crontab "$CRON_BAK"` —— 把「已禁用版」写回了备份文件本身，
//   于是 `restore()` 恢复的是禁用版 → **cron 自动部署静默停摆**，dev 卡在演练前版本数小时。
//
// 修正（本次守护的不变量）：
//   1) 备份文件在任何变换前原样写出，之后**只读**；禁用变换只作用于 `mktemp` 临时副本；
//   2) `restore()` 从原始备份恢复，并显式校验「不得残留 #DRILL# 标记」，残留则告警 + 给出人工恢复命令；
//   3) 恢复由 EXIT trap 保证（成功/失败/中断都必须回到可用状态）；
//   4) 前滚前删除 state 文件，强制 pull-deploy 重新部署（配合前滚保证，见 pull-deploy-forward-roll.test.mjs）。
//
// 说明：这些是**契约/顺序守卫**（静态断言脚本接线）。bash 的真实行为证据来自服务器上的一轮演练日志。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const drill = readFileSync(join(repoRoot, 'deploy', 'drill-rollback-dev.sh'), 'utf8');
const runbook = readFileSync(
  join(repoRoot, 'docs', 'operations', 'runbooks', 'ROLLBACK-DRILL-dev.md'),
  'utf8',
);

/** 去掉注释行后的脚本文本 —— 注释里会复述旧缺陷形态，不能当作代码断言。 */
const drillCode = drill
  .split(/\r?\n/)
  .filter((line) => !/^\s*#/.test(line))
  .join('\n');

test('DR-01 备份文件在禁用变换前原样写出', () => {
  assert.match(drillCode, /crontab -l > "\$CRON_BAK"/);
  assert.match(drillCode, /CRON_BAK=\/root\/crontab-pre-drill\.bak/);
});

test('DR-02 不得再对备份文件做原地改写（旧缺陷形态）', () => {
  assert.doesNotMatch(drillCode, /sed -i[^\n]*\$CRON_BAK/, '备份被 sed -i 改写会把禁用版写回备份');
  assert.doesNotMatch(drillCode, /crontab "\$CRON_BAK" \|\| \{ fail "crontab 写入失败"/);
});

test('DR-03 禁用变换只作用于临时副本', () => {
  assert.match(drillCode, /CRON_TMP="\$\(mktemp\)"/);
  assert.match(drillCode, /sed 's\|\^\\\(\[\^#\]\.\*pull-deploy\\\)\|#DRILL# \\1\|' "\$CRON_BAK" > "\$CRON_TMP"/);
  assert.match(drillCode, /crontab "\$CRON_TMP"/);
  assert.match(drillCode, /rm -f "\$CRON_TMP"/);
});

test('DR-04 恢复时从原始备份写回', () => {
  assert.match(drillCode, /crontab "\$CRON_BAK" && step "✅ crontab 已恢复"/);
});

test('DR-05 恢复后校验无 #DRILL# 残留，残留则给出人工恢复命令', () => {
  assert.match(drillCode, /if crontab -l \| grep -q '\^#DRILL#'; then/);
  assert.match(drillCode, /人工执行: crontab -l \| sed 's\|\^#DRILL# \|\|' \| crontab -/);
  assert.match(drillCode, /CRON_DISABLED="no"/);
});

test('DR-06 恢复由 EXIT trap 保证（任何退出路径都回到可用状态）', () => {
  assert.match(drillCode, /trap restore EXIT/);
});

test('DR-07 前滚前删除 state 文件（强制重新部署），且顺序在 pull-deploy 之前', () => {
  const rmIdx = drillCode.indexOf('rm -f "$STATE"');
  const pullIdx = drillCode.indexOf('bash deploy/pull-deploy.sh dev');
  assert.ok(rmIdx > 0, '缺少删除 state 文件的步骤');
  assert.ok(pullIdx > rmIdx, '必须先删除 state 文件再调用 pull-deploy，否则前滚会被判「无变化」跳过');
});

test('DR-08 runbook 记载该事故与修正（知识化，避免复发）', () => {
  assert.match(runbook, /crontab 恢复失效/);
  assert.match(runbook, /sed -i/);
  assert.match(runbook, /#DRILL#/);
});

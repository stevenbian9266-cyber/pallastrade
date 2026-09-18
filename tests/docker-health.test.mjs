/**
 * Docker 健康守卫回归测试（2026-09-18 bugfix）
 *
 * 背景：本地 Docker Desktop 上 `docker exec` 会「有输出但不退出」，harness 的
 * spawnSync（无超时）因此挂死；僵尸 CLI 累积后所有 docker exec 都被堵住
 * （报 cannot exec in a stopped state 而 inspect 显示 running）。
 *
 * 覆盖：探测结果分类 / 自愈动作序列 / 阻断判定 / CIM 与 ps 进程解析 /
 *      僵尸进程筛选（只清 docker exec，绝不误伤 docker compose up / logs -f）。
 * 运行：node --test tests/docker-health.test.mjs
 * 全部为纯函数用例，不触碰真实 docker。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  classifyProbe,
  recoveryPlan,
  isBlocking,
  shouldPrune,
  parseCreationDate,
  parseWindowsProcessList,
  parsePosixProcessList,
  selectStaleCliProcesses,
} from '../scripts/ops/docker-health.mjs';

test('classifyProbe — 健康探测返回 ok', () => {
  assert.equal(classifyProbe({ status: 0, stdout: 'docker-health-ok\n' }), 'ok');
});

test('classifyProbe — 超时 = CLI 挂死', () => {
  assert.equal(classifyProbe({ status: null, timedOut: true, stdout: 'docker-health-ok' }), 'cli-hung');
});

test('classifyProbe — 容器状态自相矛盾（exec 报 stopped state）', () => {
  const stderr = 'Error response from daemon: cannot exec in a stopped state';
  assert.equal(classifyProbe({ status: 128, stderr }), 'container-inconsistent');
  // 文本判据优先于超时：挂死进程最终吐出这句时，应归因到容器而不是 CLI
  assert.equal(classifyProbe({ status: null, timedOut: true, stderr }), 'container-inconsistent');
});

test('classifyProbe — 容器不存在 / 未安装 docker 不报错', () => {
  assert.equal(classifyProbe({ status: 1, stderr: 'Error: No such container: pallastrade-web-1' }), 'container-missing');
  assert.equal(classifyProbe({ spawnError: 'ENOENT' }), 'docker-unavailable');
});

test('classifyProbe — 其他失败归为 probe-failed', () => {
  assert.equal(classifyProbe({ status: 1, stderr: 'boom' }), 'probe-failed');
});

test('recoveryPlan — 只清僵尸不误伤，顺序为先清后拉', () => {
  assert.deepEqual(recoveryPlan('ok'), []);
  assert.deepEqual(recoveryPlan('docker-unavailable'), []);
  assert.deepEqual(recoveryPlan('container-missing'), []);
  assert.deepEqual(recoveryPlan('cli-hung'), ['kill-stale-cli', 'reprobe', 'start-container', 'reprobe']);
  assert.deepEqual(recoveryPlan('container-inconsistent'), ['kill-stale-cli', 'start-container', 'reprobe']);
  // 先清僵尸再拉容器：僵尸未清时 docker start 也会被堵
  const inconsistent = recoveryPlan('container-inconsistent');
  assert.ok(inconsistent.indexOf('kill-stale-cli') < inconsistent.indexOf('start-container'));
});

test('isBlocking — 不适用场景不阻断（CI / 无 Docker / 栈未启动）', () => {
  assert.equal(isBlocking('ok'), false);
  assert.equal(isBlocking('docker-unavailable'), false);
  assert.equal(isBlocking('container-missing'), false);
  assert.equal(isBlocking('cli-hung'), true);
  assert.equal(isBlocking('container-inconsistent'), true);
});

test('shouldPrune — --fix 只在异常时动手，--prune 是主动维护', () => {
  // 健康 + --fix：不动手（避免误伤正在跑的调用）
  assert.equal(shouldPrune({ classification: 'ok', fix: true }), false);
  // 异常 + --fix：清理
  assert.equal(shouldPrune({ classification: 'cli-hung', fix: true }), true);
  assert.equal(shouldPrune({ classification: 'container-inconsistent', fix: true }), true);
  // --prune：健康时也清扫历史僵尸
  assert.equal(shouldPrune({ classification: 'ok', prune: true }), true);
  // 不适用场景（CI / 无 docker）不清扫
  assert.equal(shouldPrune({ classification: 'docker-unavailable', prune: true }), false);
  assert.equal(shouldPrune({ classification: 'container-missing', prune: true }), false);
});

test('parseCreationDate — 支持 CIM /Date(...)/、ISO 与非法值', () => {
  assert.equal(parseCreationDate('/Date(1758000000000)/'), 1758000000000);
  assert.equal(parseCreationDate(1758000000000), 1758000000000);
  assert.equal(parseCreationDate('2026-09-18T05:44:12+08:00'), Date.parse('2026-09-18T05:44:12+08:00'));
  assert.equal(parseCreationDate('not-a-date'), null);
  assert.equal(parseCreationDate(null), null);
});

test('parseWindowsProcessList — 数组 / 单对象 / 空 / 坏 JSON', () => {
  const now = Date.parse('2026-09-18T12:00:00Z');
  const single = parseWindowsProcessList(
    JSON.stringify({ ProcessId: 39716, CreationDate: '/Date(1757900000000)/', CommandLine: 'docker exec pallastrade-web-1 bash -lc "echo hi"' }),
    now
  );
  assert.equal(single.length, 1);
  assert.equal(single[0].pid, 39716);
  assert.equal(single[0].ageMs, now - 1757900000000);

  const many = parseWindowsProcessList(
    [{ ProcessId: 1, CreationDate: '/Date(1757900000000)/', CommandLine: 'docker exec x bash' }, { ProcessId: 2 }],
    now
  );
  assert.equal(many.length, 2);
  assert.equal(many[1].ageMs, null);

  assert.deepEqual(parseWindowsProcessList('', now), []);
  assert.deepEqual(parseWindowsProcessList('{ not json', now), []);
});

test('parsePosixProcessList — 解析 ps -eo pid,etimes,args', () => {
  const now = Date.parse('2026-09-18T12:00:00Z');
  const rows = parsePosixProcessList(
    ['  PID ELAPSED COMMAND', '  39716     249 docker exec pallastrade-web-1 bash -lc "echo hi"', '  1 86400 /sbin/init'].join('\n'),
    now
  );
  assert.equal(rows.length, 2);
  assert.equal(rows[0].pid, 39716);
  assert.equal(rows[0].ageMs, 249_000);
  assert.match(rows[0].args, /pallastrade-web-1/);
});

test('selectStaleCliProcesses — 只清 docker exec 僵尸，绝不动 compose up / logs -f', () => {
  const processes = [
    { pid: 101, ageMs: 300_000, args: 'docker exec pallastrade-web-1 bash -lc "bundle exec rspec"' }, // 僵尸
    { pid: 102, ageMs: 300_000, args: 'docker compose up -d web worker' }, // 长任务，保留
    { pid: 103, ageMs: 300_000, args: 'docker logs -f pallastrade-web-1' }, // 长任务，保留
    { pid: 104, ageMs: 5_000, args: 'docker exec pallastrade-web-1 bash -lc "echo hi"' }, // 刚起，保留
    { pid: 105, ageMs: 300_000, args: 'docker exec other-container bash -lc "echo hi"' }, // 非目标容器
  ];
  const stale = selectStaleCliProcesses(processes, { container: 'pallastrade-web-1', minAgeMs: 120_000 });
  assert.deepEqual(stale.map((p) => p.pid), [101]);

  // 不传 container 时按 exec 语义清理（仍是同一批僵尸）
  assert.deepEqual(selectStaleCliProcesses(processes, { minAgeMs: 120_000 }).map((p) => p.pid), [101, 105]);

  // excludePids 保护（例如当前进程自身）
  assert.deepEqual(selectStaleCliProcesses(processes, { container: 'pallastrade-web-1', excludePids: [101] }), []);

  // 年龄未知（ageMs=null）不清理，避免误杀
  assert.deepEqual(selectStaleCliProcesses([{ pid: 1, ageMs: null, args: 'docker exec x bash' }], {}), []);
});

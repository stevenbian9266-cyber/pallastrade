#!/usr/bin/env node
/**
 * PALLAS-CUSTOM: dev 环境 Docker 健康守卫（2026-09-18 bugfix）
 *
 * 问题（本地 Docker Desktop / Windows 已知症状）：
 *   `docker exec` 偶发「命令已经输出结果、但 CLI 进程永不退出」——Node `spawnSync`
 *   （harness 的 `runEvidenceCommand` / `VerdictRegistry` 走的就是它，且**没有超时**）
 *   会一直等下去，于是：
 *     ① `harness verify <verifier>` 静默挂死（容器 CPU 0%、test.log 已停止写入）；
 *     ② 挂死的 CLI 进程累积成「僵尸层」，之后**所有** docker exec 都被堵住，
 *        报错变成 `cannot exec in a stopped state`，而 `docker inspect` 却显示 running=true
 *        （两条链路状态自相矛盾，重启容器也无效）。
 *
 * 处置：先用超时探测定位，再按需清理僵尸 CLI（只清 `docker exec` 且超过年龄阈值的进程，
 *       绝不动 `docker compose up` / `docker logs -f` 这类长任务），必要时 `docker start` 拉起容器。
 *
 * 用法：
 *   node scripts/ops/docker-health.mjs                 # 只诊断（默认容器 pallastrade-web-1）
 *   node scripts/ops/docker-health.mjs --fix           # 自愈：清僵尸 CLI + 必要时拉起容器
 *   node scripts/ops/docker-health.mjs --prune         # 主动维护：健康时也清历史僵尸 CLI
 *   node scripts/ops/docker-health.mjs --json          # 机器可读输出
 *   node scripts/ops/docker-health.mjs --warn-only     # 永不失败（给 pre-commit 当提示用）
 *   node scripts/ops/docker-health.mjs --container X --probe-timeout 10000 --attempts 2
 *
 * 退出码：0 = 健康 / 不适用 /（--fix 后）已恢复；1 = 仍不健康且未修复。
 */
import { spawnSync } from 'node:child_process';

export const DEFAULT_CONTAINER = 'pallastrade-web-1';
export const DEFAULT_PROBE_TIMEOUT_MS = 10_000;
export const DEFAULT_ATTEMPTS = 2;
export const DEFAULT_STALE_AGE_MS = 120_000; // 2 分钟内结束的 exec 属于正常调用，不清理

// ────────────────────────────────────────────────────────────────
// 纯函数（可单测，不依赖 docker / PowerShell）
// ────────────────────────────────────────────────────────────────

/** 把一次探测结果归类为诊断结论。 */
export function classifyProbe({ status, timedOut, spawnError, stdout = '', stderr = '' } = {}) {
  if (spawnError === 'ENOENT') return 'docker-unavailable';
  const text = `${stdout}\n${stderr}`;
  if (/No such container/i.test(text)) return 'container-missing';
  if (/cannot exec in a stopped state/i.test(text)) return 'container-inconsistent';
  if (timedOut) return 'cli-hung';
  if (status === 0) return 'ok';
  return 'probe-failed';
}

/** 该诊断结论对应的自愈动作序列（顺序即执行顺序）。 */
export function recoveryPlan(classification) {
  switch (classification) {
    case 'ok':
      return [];
    case 'docker-unavailable':
    case 'container-missing':
      return [];
    case 'cli-hung':
      return ['kill-stale-cli', 'reprobe', 'start-container', 'reprobe'];
    case 'container-inconsistent':
      return ['kill-stale-cli', 'start-container', 'reprobe'];
    default:
      return ['kill-stale-cli', 'reprobe'];
  }
}

/** 是否需要人工可见的失败（不适用场景返回 false，避免 CI/无 Docker 环境误报）。 */
export function isBlocking(classification) {
  return !['ok', 'docker-unavailable', 'container-missing'].includes(classification);
}

/**
 * 是否应清理僵尸 CLI：
 *  - `--prune`：日常维护，即使当前探测健康也清扫历史僵尸（它们正是堵死的根源）；
 *  - `--fix`：不健康时自愈（健康时不动，避免误伤正在跑的调用）。
 */
export function shouldPrune({ classification, prune = false, fix = false } = {}) {
  if (prune) return isBlocking(classification) || classification === 'ok';
  return fix && isBlocking(classification);
}

/** Windows CIM DateTime / ISO 字符串 → 毫秒时间戳；无法解析返回 null。 */
export function parseCreationDate(value) {
  if (value == null) return null;
  if (typeof value === 'number') return value;
  const text = String(value);
  const cim = text.match(/\/Date\((\d+)([+-]\d{4})?\)\//);
  if (cim) return Number(cim[1]);
  const parsed = Date.parse(text);
  return Number.isNaN(parsed) ? null : parsed;
}

/** `Get-CimInstance Win32_Process | ConvertTo-Json` 输出 → [{ pid, ageMs, args }] */
export function parseWindowsProcessList(raw, now = Date.now()) {
  let parsed = raw;
  if (typeof raw === 'string') {
    const text = raw.trim();
    if (!text) return [];
    try {
      parsed = JSON.parse(text);
    } catch {
      return [];
    }
  }
  const list = Array.isArray(parsed) ? parsed : parsed ? [parsed] : [];
  return list
    .map((entry) => {
      const pid = Number(entry?.ProcessId);
      if (!Number.isFinite(pid)) return null;
      const created = parseCreationDate(entry?.CreationDate);
      return {
        pid,
        ageMs: created == null ? null : Math.max(0, now - created),
        args: String(entry?.CommandLine || ''),
      };
    })
    .filter(Boolean);
}

/** `ps -eo pid,etimes,args` 输出 → [{ pid, ageMs, args }] */
export function parsePosixProcessList(raw, now = Date.now()) {
  return String(raw || '')
    .split('\n')
    .slice(1) // 表头
    .map((line) => {
      const match = line.trim().match(/^(\d+)\s+(\d+)\s+(.*)$/);
      if (!match) return null;
      return {
        pid: Number(match[1]),
        ageMs: Number(match[2]) * 1000,
        args: match[3],
        observedAt: now,
      };
    })
    .filter(Boolean);
}

/**
 * 挑出「僵尸 CLI」：必须是 docker **exec** 会话（绝不误伤 compose up / logs -f）、
 * 存活超过 minAgeMs、且（给定容器时）指向目标容器。
 */
export function selectStaleCliProcesses(processes, options = {}) {
  const {
    minAgeMs = DEFAULT_STALE_AGE_MS,
    container = null,
    excludePids = [],
  } = options;
  const exclude = new Set(excludePids.map(Number).filter(Number.isFinite));
  return (processes || []).filter((proc) => {
    if (!proc) return false;
    if (exclude.has(Number(proc.pid))) return false;
    if (!Number.isFinite(proc.ageMs) || proc.ageMs < minAgeMs) return false;
    const args = String(proc.args || '');
    if (!/\bexec\b/.test(args)) return false;
    if (container && !args.includes(container)) return false;
    return true;
  });
}

// ────────────────────────────────────────────────────────────────
// 运行时（spawn 封装，全部带超时——绝不允许自己变成新的僵尸）
// ────────────────────────────────────────────────────────────────

function run(command, args, { timeout = 15_000, shell = false } = {}) {
  const result = spawnSync(command, args, {
    encoding: 'utf-8',
    timeout,
    shell,
    windowsHide: true,
  });
  return {
    status: result.status,
    timedOut: result.error?.code === 'ETIMEDOUT',
    spawnError: result.error?.code ?? null,
    stdout: result.stdout || '',
    stderr: result.stderr || '',
  };
}

export function probeContainer(container, probeTimeoutMs = DEFAULT_PROBE_TIMEOUT_MS, runner = run) {
  return classifyProbe(
    runner('docker', ['exec', container, 'bash', '-lc', 'echo docker-health-ok'], { timeout: probeTimeoutMs })
  );
}

export function listDockerCliProcesses(platform = process.platform, runner = run, now = Date.now()) {
  if (platform === 'win32') {
    const result = runner(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "Get-CimInstance Win32_Process -Filter \"Name='docker.exe'\" | Select-Object ProcessId,CreationDate,CommandLine | ConvertTo-Json -Compress -Depth 3",
      ],
      { timeout: 20_000 }
    );
    if (result.status !== 0) return [];
    return parseWindowsProcessList(result.stdout, now);
  }
  const result = runner('ps', ['-eo', 'pid,etimes,args'], { timeout: 10_000 });
  if (result.status !== 0) return [];
  return parsePosixProcessList(result.stdout, now).filter((proc) => /\bdocker\b/.test(proc.args));
}

export function killProcesses(pids, platform = process.platform, runner = run) {
  const killed = [];
  for (const pid of pids) {
    const result =
      platform === 'win32'
        ? runner('taskkill', ['/PID', String(pid), '/F'], { timeout: 10_000 })
        : runner('kill', ['-9', String(pid)], { timeout: 5_000 });
    if (result.status === 0) killed.push(pid);
  }
  return killed;
}

export function startContainer(container, runner = run) {
  const result = runner('docker', ['start', container], { timeout: 120_000 });
  return { ok: result.status === 0, detail: (result.stdout || result.stderr || '').trim() };
}

/** 探测 attempts 次，互为确认，避免把「启动慢」误判为卡死。 */
export function probeWithRetries(container, { probeTimeoutMs, attempts }, runner = run) {
  let last = 'probe-failed';
  for (let i = 0; i < attempts; i += 1) {
    last = probeContainer(container, probeTimeoutMs, runner);
    if (last === 'ok') return 'ok';
    if (last === 'docker-unavailable' || last === 'container-missing') return last;
  }
  return last;
}

// ────────────────────────────────────────────────────────────────
// CLI
// ────────────────────────────────────────────────────────────────

function parseArgs(argv) {
  const readFlag = (name, fallback) => {
    const index = argv.indexOf(name);
    return index === -1 ? fallback : argv[index + 1];
  };
  return {
    container: readFlag('--container', DEFAULT_CONTAINER),
    probeTimeoutMs: Number(readFlag('--probe-timeout', DEFAULT_PROBE_TIMEOUT_MS)),
    attempts: Number(readFlag('--attempts', DEFAULT_ATTEMPTS)),
    staleAgeMs: Number(readFlag('--stale-age', DEFAULT_STALE_AGE_MS)),
    fix: argv.includes('--fix'),
    prune: argv.includes('--prune'),
    json: argv.includes('--json'),
    warnOnly: argv.includes('--warn-only'),
  };
}

const MESSAGES = {
  ok: '✅ docker exec 正常',
  'docker-unavailable': 'ℹ️  未检测到 docker CLI —— 跳过（CI / 无 Docker 环境）',
  'container-missing': `ℹ️  容器不存在（dev 栈未启动？）—— 跳过`,
  'cli-hung': '❌ docker exec 无响应（CLI 挂死：命令可能已执行，但进程不退出）',
  'container-inconsistent': '❌ 容器状态自相矛盾（exec 报 stopped state，但 inspect 显示 running）',
  'probe-failed': '❌ docker exec 探测失败',
};

function main(argv) {
  const options = parseArgs(argv);
  const report = { container: options.container, steps: [], stalePids: [], killedPids: [], final: null };

  let classification = probeWithRetries(options.container, options);
  const unhealthy = classification === 'cli-hung' || classification === 'container-inconsistent' || classification === 'probe-failed';

  // 清理僵尸 CLI：--fix 仅在不健康时动手；--prune 是主动维护（健康也清历史僵尸）
  if (shouldPrune({ classification, prune: options.prune, fix: options.fix })) {
    const processes = listDockerCliProcesses();
    const stale = selectStaleCliProcesses(processes, {
      minAgeMs: options.staleAgeMs,
      container: options.container,
    });
    report.stalePids = stale.map((proc) => proc.pid);

    if (report.stalePids.length) {
      report.killedPids = killProcesses(report.stalePids);
      report.steps.push(`已清理僵尸 docker exec CLI 进程：${report.killedPids.join(', ') || '（无）'}`);
    } else {
      report.steps.push('未发现僵尸 docker exec CLI 进程');
    }

    if (unhealthy) {
      // 清了僵尸后重探；仍不健康（且非不适用）则拉起容器
      let afterKill = probeWithRetries(options.container, options);
      if (afterKill !== 'ok' && afterKill !== 'docker-unavailable' && afterKill !== 'container-missing') {
        const started = startContainer(options.container);
        report.steps.push(`docker start ${options.container} → ${started.ok ? 'ok' : `失败：${started.detail}`}`);
        for (let i = 0; i < 12 && afterKill !== 'ok'; i += 1) {
          afterKill = probeWithRetries(options.container, options);
          if (afterKill === 'ok') break;
          report.steps.push(`等待容器就绪（第 ${i + 1} 次重探：${afterKill}）`);
        }
      }
      classification = afterKill;
    } else if (report.killedPids.length) {
      // 清扫后确认环境仍然可用
      classification = probeWithRetries(options.container, options);
    }
  }

  report.final = classification;
  const healthy = ['ok', 'docker-unavailable', 'container-missing'].includes(classification);

  if (options.json) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    console.log(MESSAGES[classification] || MESSAGES['probe-failed']);
    report.steps.forEach((step) => console.log(`   · ${step}`));
    if (!healthy) {
      console.log(`   → 自愈：npm run docker:health:fix    （或 node scripts/ops/docker-health.mjs --fix）`);
      console.log(`   → 说明：见 ai/skills/pallastrade-deployment/SKILL.md「本地 Docker exec 卡死」`);
    }
  }

  if (!healthy && !options.warnOnly) process.exitCode = 1;
}

const invokedDirectly = process.argv[1] && process.argv[1].replace(/\\/g, '/').endsWith('scripts/ops/docker-health.mjs');
if (invokedDirectly) main(process.argv.slice(2));

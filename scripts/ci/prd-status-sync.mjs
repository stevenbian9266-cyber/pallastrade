#!/usr/bin/env node
/**
 * PRD 状态一致性检查器
 *
 * 关联 PRD：docs/prd/harness/PRD-20260913-harness-prd-状态一致性检查器-*.md
 * 关联 REQ：harness/requirements/REQ-20260913-prd-status-sync.md
 *
 * 解决的问题（2026-09-13 实测）：
 *   1. docs/prd/README.md 索引与各 PRD 文件头状态可能不一致（收口前漂移 25 处），
 *      而 .github/workflows 中没有任何 PRD 检查 → 漂移只能靠人工审计发现。
 *   2. harness 引擎用 `/\| 状态 \| ([^|]+) \|/`（单空格）解析状态，补空格的表格行
 *      对它不可见（当前 4/117 份 PRD 受影响）。
 *
 * 用法：
 *   node scripts/ci/prd-status-sync.mjs [--check] [--fix] [--json] [--root <dir>]
 *
 * 退出码：0 = 一致；1 = 发现漂移；2 = 用法/IO 错误
 *
 * 设计约束（见 PRD §4 NFR）：零第三方依赖、确定性、--fix 不新建/不删除文件。
 */
import { readFileSync, writeFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join, relative, dirname, basename, sep } from 'node:path';
import { pathToFileURL } from 'node:url';
import process from 'node:process';

/** 引擎词表（node_modules/pallastrade-harness/bin/docs-gen.mjs） */
export const ENGINE_STATUSES = [
  'draft',
  'reviewing',
  'approved',
  'implementing',
  'verifying',
  'done',
  'rejected',
];
/** 仓库扩展词表（引擎未含，但仓库在用） */
export const REPO_STATUSES = ['merged', 'obsolete'];
export const ALL_STATUSES = [...ENGINE_STATUSES, ...REPO_STATUSES];

const STATUS_ROW_LOOSE = /^\|\s*状态\s*\|\s*(.*?)\s*\|\s*$/m;
// 与引擎同口径：`| 状态 | ` 必须是「单空格 + 竖线」，因此补空格的表格行对引擎不可见。
// （引擎原文见 node_modules/pallastrade-harness/bin/harness.mjs：/\| 状态 \| ([^|]+) \|/）
const STATUS_ROW_ENGINE = /^\| 状态 \| [^|]+\|\s*$/m;
const INDEX_ROW = /^\|\s*([^|]*?)\s*\|\s*(PRD-[^|]*?)\s*\|\s*([^|]*?)\s*\|\s*([^|]*?)\s*\|\s*([^|]*?)\s*\|\s*$/;

/** 把状态单元格原文归一为词表值；无法识别返回 null */
export function normalizeStatus(raw) {
  const v = String(raw ?? '').trim();
  if (!v) return null;
  if (v.includes('废弃')) return 'obsolete';
  const token = v.split(/[\s（(【:：|/]/)[0].toLowerCase();
  return ALL_STATUSES.includes(token) ? token : null;
}

/** 解析单个 PRD 文件的状态 */
export function parsePrdStatus(text) {
  const engineVisible = STATUS_ROW_ENGINE.test(text);
  const m = text.match(STATUS_ROW_LOOSE);
  if (!m) return { status: null, engineVisible: false, raw: null };
  return { status: normalizeStatus(m[1]), engineVisible, raw: m[1] };
}

function walkPrdFiles(dir, out = []) {
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    let st;
    try {
      st = statSync(full);
    } catch {
      continue;
    }
    if (st.isDirectory()) walkPrdFiles(full, out);
    else if (/^PRD-.*\.md$/.test(name)) out.push(full);
  }
  return out;
}

/** 解析 README 索引表 */
export function parseIndex(text) {
  const lines = text.split(/\r?\n/);
  const entries = new Map();
  lines.forEach((line, i) => {
    const m = line.match(INDEX_ROW);
    if (!m) return;
    const [, rawStatus, name, category, date, req] = m;
    entries.set(name.trim(), {
      name: name.trim(),
      rawStatus: rawStatus.trim(),
      status: normalizeStatus(rawStatus),
      category: category.trim(),
      date: date.trim(),
      req: req.trim(),
      line: i + 1,
    });
  });
  return entries;
}

function categoryOf(file) {
  // docs/prd/<category>/PRD-YYYYMMDD-<category>-<slug>.md
  const parts = file.split(/[\\/]/);
  const i = parts.indexOf('prd');
  return i >= 0 && parts[i + 1] ? parts[i + 1] : 'other';
}

function dateOf(name) {
  const m = name.match(/^PRD-(\d{4})(\d{2})(\d{2})-/);
  return m ? `${m[1]}-${m[2]}-${m[3]}` : '';
}

/**
 * 分析仓库，返回 { ok, issues, files, index }。
 * issue.type ∈ state-drift | not-indexed | missing-file | unparsable-status-row
 */
export function analyze(root) {
  const prdDir = join(root, 'docs', 'prd');
  const readmePath = join(prdDir, 'README.md');
  const issues = [];

  if (!existsSync(readmePath)) {
    return { ok: false, issues: [{ type: 'io-error', message: `missing ${readmePath}` }], files: [], index: new Map() };
  }

  const readmeText = readFileSync(readmePath, 'utf8');
  const index = parseIndex(readmeText);

  const files = walkPrdFiles(prdDir).map((abs) => {
    const text = readFileSync(abs, 'utf8');
    const name = basename(abs, '.md');
    return { abs, name, rel: relative(root, abs).split(sep).join('/'), ...parsePrdStatus(text) };
  });

  const byName = new Map(files.map((f) => [f.name, f]));

  for (const entry of index.values()) {
    const file = byName.get(entry.name);
    if (!file) {
      issues.push({
        type: 'missing-file',
        prd: entry.name,
        indexStatus: entry.status,
        message: `索引引用的 PRD 文件不存在：${entry.name}`,
      });
      continue;
    }
    if (entry.status !== file.status) {
      issues.push({
        type: 'state-drift',
        prd: entry.name,
        rel: file.rel,
        indexStatus: entry.status,
        fileStatus: file.status,
        indexRaw: entry.rawStatus,
        message: `状态漂移：索引=${entry.status ?? `?(${entry.rawStatus})`} 文件=${file.status ?? '?'}`,
      });
    }
  }

  for (const file of files) {
    if (!index.has(file.name)) {
      issues.push({
        type: 'not-indexed',
        prd: file.name,
        rel: file.rel,
        fileStatus: file.status,
        message: `PRD 未登记进 docs/prd/README.md 索引：${file.name}`,
      });
    }
    if (file.status === null || !file.engineVisible) {
      issues.push({
        type: 'unparsable-status-row',
        prd: file.name,
        rel: file.rel,
        fileStatus: file.status,
        engineVisible: file.engineVisible,
        message: file.engineVisible
          ? `状态行存在但状态词不在词表内：${String(file.raw).trim()}`
          : '状态行无法被引擎解析（缺失 `| 状态 | … |` 或制表符/补空格导致不可见）',
      });
    }
  }

  return { ok: issues.length === 0, issues, files, index, readmePath, readmeText };
}

/** 以文件头状态为准修复索引（不新建/不删除文件） */
export function applyFix(root) {
  const result = analyze(root);
  const fixable = result.issues.filter((i) => i.type === 'state-drift' || i.type === 'not-indexed');

  const byName = new Map(result.files.map((f) => [f.name, f]));
  let lines = result.readmeText.split(/\r?\n/);
  let lastTableLine = -1;

  lines = lines.map((line, i) => {
    const m = line.match(INDEX_ROW);
    if (!m) {
      // 表格分隔行（|---|---|）作为插入点回退，兼容「索引表尚无数据行」的仓库
      if (/^\|[\s:|-]+\|\s*$/.test(line) && /-/.test(line)) lastTableLine = i;
      return line;
    }
    lastTableLine = i;
    const name = m[2].trim();
    const file = byName.get(name);
    if (!file || file.status === null) return line;
    if (normalizeStatus(m[1]) === file.status) return line;
    return `| ${file.status} | ${name} | ${m[3].trim()} | ${m[4].trim()} | ${m[5].trim()} |`;
  });

  const appended = [];
  for (const issue of fixable) {
    if (issue.type !== 'not-indexed') continue;
    const file = byName.get(issue.prd);
    if (!file || file.status === null) continue;
    appended.push(`| ${file.status} | ${file.name} | ${categoryOf(file.rel)} | ${dateOf(file.name)} | （实施时回填） |`);
  }
  if (appended.length && lastTableLine >= 0) {
    lines.splice(lastTableLine + 1, 0, ...appended);
  }

  writeFileSync(result.readmePath, lines.join('\n'), 'utf8');

  // 归一化「引擎不可见」的状态行（补空格 / 制表符）：语义不变，仅把格式对齐引擎口径。
  // 词表图例行（'draft / reviewing / …'）不动。
  const normalizedRows = [];
  for (const issue of result.issues) {
    if (issue.type !== 'unparsable-status-row') continue;
    const file = byName.get(issue.prd);
    if (!file || file.status === null || file.engineVisible) continue;
    if (String(file.raw ?? '').includes(' / ')) continue;
    const text = readFileSync(file.abs, 'utf8');
    const next = text.replace(STATUS_ROW_LOOSE, `| 状态 | ${file.status} |`);
    if (next !== text) {
      writeFileSync(file.abs, next, 'utf8');
      normalizedRows.push(file.rel);
    }
  }

  const remaining = analyze(root).issues;
  return { changed: fixable.length + normalizedRows.length, unfixable: remaining, normalizedRows };
}

function usage() {
  console.log('用法: node scripts/ci/prd-status-sync.mjs [--check] [--fix] [--json] [--root <dir>]');
  console.log('  --check  只检查（默认）；发现漂移退出码 1');
  console.log('  --fix    以 PRD 文件头状态为准回写 docs/prd/README.md 索引，并归一化引擎不可见的状态行');
  console.log('  --json   机器可读输出');
}

function main(argv) {
  const opts = { mode: 'check', json: false, root: process.cwd() };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--fix') opts.mode = 'fix';
    else if (a === '--check') opts.mode = 'check';
    else if (a === '--json') opts.json = true;
    else if (a === '--root') opts.root = argv[++i];
    else if (a === '--help' || a === '-h') return usage(), 0;
    else {
      console.error(`未知参数: ${a}`);
      usage();
      return 2;
    }
  }

  try {
    if (opts.mode === 'fix') {
      const { changed, unfixable } = applyFix(opts.root);
      const after = analyze(opts.root);
      if (opts.json) {
        console.log(JSON.stringify({ fixed: changed, remaining: after.issues }, null, 2));
      } else {
        console.log(`✅ 已修复 ${changed} 处索引状态`);
        for (const i of unfixable) console.log(`⚠️  未能自动修复（${i.type}）：${i.message}`);
        console.log(after.ok ? '✅ 复检通过：索引与文件状态一致' : `❌ 复检仍有 ${after.issues.length} 处问题`);
      }
      return after.ok ? 0 : 1;
    }

    const result = analyze(opts.root);
    if (opts.json) {
      console.log(JSON.stringify({ ok: result.ok, issues: result.issues }, null, 2));
    } else if (result.ok) {
      console.log(`✅ PRD 状态一致（${result.files.length} 份文件 / ${result.index.size} 行索引）`);
    } else {
      console.error(`❌ PRD 状态不一致：${result.issues.length} 处`);
      for (const i of result.issues) console.error(`   [${i.type}] ${i.message}`);
      console.error('   修复：node scripts/ci/prd-status-sync.mjs --fix');
    }
    return result.ok ? 0 : 1;
  } catch (err) {
    console.error(`❌ 执行失败：${err && err.message ? err.message : err}`);
    return 2;
  }
}

const isMain =
  Boolean(process.argv[1]) && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isMain) process.exit(main(process.argv.slice(2)));

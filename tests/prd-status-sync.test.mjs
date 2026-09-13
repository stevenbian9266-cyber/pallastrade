/**
 * PRD 状态一致性检查器回归测试
 *
 * 关联 PRD：docs/prd/harness/PRD-20260913-harness-prd-状态一致性检查器-*.md
 * 覆盖：AC-002（state-drift）/ AC-003（--fix）/ AC-004（unparsable-status-row）/ AC-006（not-indexed）
 * 运行：node --test tests/
 *
 * 全部用例在 os.tmpdir() 内构造 mini 仓库树，不触碰真实仓库。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { analyze, applyFix, parseIndex, normalizeStatus } from '../scripts/ci/prd-status-sync.mjs';

const README_HEADER = [
  '# 测试用 PRD 索引',
  '',
  '| 状态 | PRD | 分类 | 日期 | 关联 REQ |',
  '|---|---|---|---|---|',
];

function makeRepo({ readmeRows = [], prds = [] }) {
  const root = mkdtempSync(join(tmpdir(), 'prd-status-'));
  const prdDir = join(root, 'docs', 'prd');
  mkdirSync(prdDir, { recursive: true });
  writeFileSync(
    join(prdDir, 'README.md'),
    [...README_HEADER, ...readmeRows, '', '## 使用流程', ''].join('\n'),
    'utf8',
  );
  for (const p of prds) {
    const dir = join(prdDir, p.category);
    mkdirSync(dir, { recursive: true });
    const statusLine = p.statusRow ?? (p.status ? `| 状态 | ${p.status} |` : null);
    const body = [`# ${p.name}`, '', '| 元数据 | 值 |', '|---|---|'];
    if (statusLine) body.push(statusLine);
    body.push('| 创建日期 | 2026-01-01 |', '');
    writeFileSync(join(dir, `${p.name}.md`), body.join('\n'), 'utf8');
  }
  return root;
}

function cleanup(root) {
  rmSync(root, { recursive: true, force: true });
}

test('词表归一：引擎词表 + 仓库扩展 + 废弃', () => {
  assert.equal(normalizeStatus('done'), 'done');
  assert.equal(normalizeStatus('done（2026-09-13 收口）'), 'done');
  assert.equal(normalizeStatus('⛔ 废弃（2026-08-14）'), 'obsolete');
  assert.equal(normalizeStatus('merged（与 checkout-p7 同需求）'), 'merged');
  assert.equal(normalizeStatus('draft / reviewing / approved'), 'draft'); // 词表图例行按首词解析
  assert.equal(normalizeStatus('bogus'), null);
});

// AC-002：索引 done，文件 approved → state-drift
test('AC-002 检出 state-drift（索引与文件不一致）', () => {
  const root = makeRepo({
    readmeRows: ['| done | PRD-20260101-demo-alpha | demo | 2026-01-01 | REQ-x.md |'],
    prds: [{ category: 'demo', name: 'PRD-20260101-demo-alpha', status: 'approved' }],
  });
  try {
    const r = analyze(root);
    assert.equal(r.ok, false);
    const drift = r.issues.filter((i) => i.type === 'state-drift');
    assert.equal(drift.length, 1);
    assert.equal(drift[0].indexStatus, 'done');
    assert.equal(drift[0].fileStatus, 'approved');
  } finally {
    cleanup(root);
  }
});

// AC-003：--fix 后复检为 0（幂等）
test('AC-003 applyFix 以文件头为准回写索引，复检通过', () => {
  const root = makeRepo({
    readmeRows: [
      '| done | PRD-20260101-demo-alpha | demo | 2026-01-01 | REQ-x.md |',
      '| approved | PRD-20260102-demo-beta | demo | 2026-01-02 | REQ-y.md |',
    ],
    prds: [
      { category: 'demo', name: 'PRD-20260101-demo-alpha', status: 'approved' },
      { category: 'demo', name: 'PRD-20260102-demo-beta', status: 'done' },
    ],
  });
  try {
    assert.equal(analyze(root).ok, false);
    const { changed } = applyFix(root);
    assert.equal(changed, 2);
    const after = analyze(root);
    assert.equal(after.ok, true, JSON.stringify(after.issues));

    const readme = readFileSync(join(root, 'docs', 'prd', 'README.md'), 'utf8');
    const idx = parseIndex(readme);
    assert.equal(idx.get('PRD-20260101-demo-alpha').status, 'approved');
    assert.equal(idx.get('PRD-20260102-demo-beta').status, 'done');
    // 非状态列保持不变
    assert.equal(idx.get('PRD-20260101-demo-alpha').req, 'REQ-x.md');
    assert.match(readme, /## 使用流程/); // 表格以外的内容未被破坏
  } finally {
    cleanup(root);
  }
});

// AC-004：补空格状态行（引擎不可见）
test('AC-004 检出 unparsable-status-row（制表/补空格导致引擎不可见）', () => {
  const root = makeRepo({
    readmeRows: ['| done | PRD-20260101-demo-gamma | demo | 2026-01-01 | REQ-z.md |'],
    prds: [
      {
        category: 'demo',
        name: 'PRD-20260101-demo-gamma',
        statusRow: '| 状态       | done                                                       |',
      },
    ],
  });
  try {
    const r = analyze(root);
    const unparsable = r.issues.filter((i) => i.type === 'unparsable-status-row');
    assert.equal(unparsable.length, 1);
    assert.equal(unparsable[0].engineVisible, false);
    // 状态值本身仍能被宽松解析出来（因此不产生 state-drift）
    assert.equal(r.issues.filter((i) => i.type === 'state-drift').length, 0);
  } finally {
    cleanup(root);
  }
});

// AC-004c：--fix 把补空格状态行归一化为引擎口径
test('AC-004c applyFix 归一化补空格状态行，复检通过且可被引擎解析', () => {
  const root = makeRepo({
    readmeRows: ['| done | PRD-20260101-demo-gamma | demo | 2026-01-01 | REQ-z.md |'],
    prds: [
      {
        category: 'demo',
        name: 'PRD-20260101-demo-gamma',
        statusRow: '| 状态       | done                                                       |',
      },
    ],
  });
  try {
    const { normalizedRows } = applyFix(root);
    assert.equal(normalizedRows.length, 1);
    const after = analyze(root);
    assert.equal(after.ok, true, JSON.stringify(after.issues));

    const text = readFileSync(join(root, 'docs', 'prd', 'demo', 'PRD-20260101-demo-gamma.md'), 'utf8');
    assert.match(text, /^\| 状态 \| done \|$/m); // 引擎可解析格式
  } finally {
    cleanup(root);
  }
});

test('AC-004b 完全缺失状态行 → unparsable-status-row', () => {
  const root = makeRepo({
    readmeRows: ['| done | PRD-20260101-demo-delta | demo | 2026-01-01 | REQ-w.md |'],
    prds: [{ category: 'demo', name: 'PRD-20260101-demo-delta', statusRow: null }],
  });
  try {
    const r = analyze(root);
    const unparsable = r.issues.filter((i) => i.type === 'unparsable-status-row');
    assert.equal(unparsable.length, 1);
    assert.equal(unparsable[0].fileStatus, null);
  } finally {
    cleanup(root);
  }
});

// AC-006：文件未进索引
test('AC-006 检出 not-indexed，且 applyFix 会补行', () => {
  const root = makeRepo({
    readmeRows: [],
    prds: [{ category: 'demo', name: 'PRD-20260101-demo-eps', status: 'done' }],
  });
  try {
    const r = analyze(root);
    const notIndexed = r.issues.filter((i) => i.type === 'not-indexed');
    assert.equal(notIndexed.length, 1);

    applyFix(root);
    const after = analyze(root);
    assert.equal(after.ok, true, JSON.stringify(after.issues));
    const idx = parseIndex(readFileSync(join(root, 'docs', 'prd', 'README.md'), 'utf8'));
    const row = idx.get('PRD-20260101-demo-eps');
    assert.ok(row, '新行已补入索引');
    assert.equal(row.status, 'done');
    assert.equal(row.category, 'demo');
    assert.equal(row.date, '2026-01-01');
  } finally {
    cleanup(root);
  }
});

// 索引指向不存在的文件
test('检出 missing-file（索引里的 PRD 无对应文件）', () => {
  const root = makeRepo({
    readmeRows: ['| done | PRD-20260101-demo-zeta | demo | 2026-01-01 | REQ-v.md |'],
    prds: [],
  });
  try {
    const r = analyze(root);
    const missing = r.issues.filter((i) => i.type === 'missing-file');
    assert.equal(missing.length, 1);
  } finally {
    cleanup(root);
  }
});

test('一致时返回 ok（无问题）', () => {
  const root = makeRepo({
    readmeRows: ['| done | PRD-20260101-demo-eta | demo | 2026-01-01 | REQ-u.md |'],
    prds: [{ category: 'demo', name: 'PRD-20260101-demo-eta', status: 'done' }],
  });
  try {
    assert.equal(analyze(root).ok, true);
  } finally {
    cleanup(root);
  }
});

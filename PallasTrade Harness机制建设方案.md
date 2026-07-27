# PallasTrade Harness 机制建设方案（完整细化版）

> 写给 Steven Bian（独立开发者）
> 目标：用最少的精力，建成能让你和客户都安心的工程质量体系
> 版本：v2 — 每步可精确执行
> 日期：2026-07-27

---

## 一、你的真实处境

### 你已经做到的

PallasTrade 不是一个从零开始的项目。你已完成一轮高质量的自有化工程改造：

- **单仓库结构**定型：`backend/`（Rails）、`platform/`（TypeScript SDK/CLI/Dashboard）、`storefront/`（Next.js）、`ai/`（AI Skills）
- **API 统一到 V3**，V1/V2 已删除并由 CI 契约防止回流
- **13 个本地 Gem** 固定为无版本后缀目录，Gemfile/锁文件/CI 全部同步
- **品牌归属** 零残留，物理扫描通过
- **根级 CI** 已有 6 个 workflow，三个组件 CI 全部通过
- **AI Skills** 已有 24 个领域技能 + 2 个命令 + 2 个安全钩子

### 你还缺的（痛点清单）

1. AI 读的 Skill 路径是错的 → 写的代码不可靠
2. 测试大半没在 CI 里跑 → 测试形同虚设
3. 没有覆盖率底线 → 不知道哪些代码没被测
4. 升级像赌博 → 不敢给客户升级
5. 交付靠嘴说 → 拿不出结构化证据
6. **代码改了，文档没改** → 知识资产持续贬值

---

## 二、九项核心能力（目标）

| # | 能力 | 一句话 |
|---|---|---|
| ① | AI 只读真信息 | 所有 Skill/指令中的路径与真实代码库一致 |
| ② | AI 写不出屎山 | 反模式在 commit 阶段被物理拦截 |
| ③ | AI 做不了危险操作 | Shell 级 Hook 阻断破坏性命令 |
| ④ | 5 分钟知道能不能 push | quick profile 即时反馈 |
| ⑤ | 测试不是摆设 | 全量测试接入 CI 自动执行 |
| ⑥ | 升级像拨开关 | audit→baseline→upgrade→verify→rollback |
| ⑦ | 交付 = 交证据 | 每次交付自动生成证据包 |
| ⑧ | 系统越用越强 | 每次踩坑变成一条新规则 |
| ⑨ | 代码和知识永远同步 | `doc-impact` 检查确保文档随代码更新 |

---

## 三、建设路线：四步走，不可跳步

---

### 第 1 步：让 AI 认识真实项目

**总耗时**：3-5 天（约 25-35 小时）
**前置条件**：无，可立即开始
**目标**：消除所有工程指令与真实代码库之间的漂移

---

#### 子步骤 1.1：修正 `platform/CLAUDE.md`（3 小时）

**涉及文件**：`d:\pallastrade\platform\CLAUDE.md`

**操作**：打开文件，执行以下全局查找替换。每完成一处替换，立刻用验证命令确认。

| 序号 | 查找内容 | 替换为 | 验证命令 |
|---|---|---|---|
| 1.1a | `pallastrade/core` | `backend/pallastrade_gems/pallastrade_core` | `grep -n "pallastrade/core" platform/CLAUDE.md` → 应为空 |
| 1.1b | `pallastrade/api`（指 gem 目录的上下文） | `backend/pallastrade_gems/pallastrade_api` | `grep -n "pallastrade/api" platform/CLAUDE.md` → 检查剩余匹配是否合理 |
| 1.1c | `pallastrade/emails` | `backend/pallastrade_gems/pallastrade_emails` | — |
| 1.1d | `pallastrade/dashboard`（指 gem 的上下文） | `backend/pallastrade_gems/pallastrade_dashboard` | — |
| 1.1e | `server/`（指 Rails 应用根目录的上下文） | `backend/` | `grep -n '\bserver/' platform/CLAUDE.md` → 检查剩余匹配（`pnpm server:*` 脚本名不需要改） |
| 1.1f | `packages/sdk` | `platform/packages/sdk` | — |
| 1.1g | `packages/admin-sdk` | `platform/packages/admin-sdk` | — |
| 1.1h | `packages/cli` | `platform/packages/cli` | — |
| 1.1i | `packages/dashboard` | `platform/packages/dashboard` | — |
| 1.1j | `packages/dashboard-ui` | `platform/packages/dashboard-ui` | — |
| 1.1k | `packages/dashboard-core` | `platform/packages/dashboard-core` | — |

**注意区分**：`pallastrade/core` 作为 Ruby gem 名称的引用需要改，但 `pallastrade_core`（带下划线的 gem 实际名称）不需要改。同样，`PallasTrade::Core`（Ruby 命名空间）不需要改。

**如果部分匹配不确定是否该改**：在行末加注释 `# TODO: verify path after harness migration`，不要做猜测性修改。

**产出物**：`platform/CLAUDE.md`（已修正）

---

#### 子步骤 1.2：修正 `backend/CLAUDE.md`（1 小时）

**涉及文件**：`d:\pallastrade\backend\CLAUDE.md`

**操作**：找到包含以下关键词的段落，整体替换。

**查找关键词**（任意一个即命中）：
- `不要修改` `Gem` `源码`
- `do not modify` `gem` `source`
- `don't modify` `gem`

**替换为以下段落**（可直接复制粘贴）：

```markdown
## Modifying PallasTrade Source

The gems under `pallastrade_gems/` are **first-party owned source**.
You may modify them. Follow this priority order when choosing your approach:

| Priority | Approach | When |
|---|---|---|
| 1 | **Decorator** (`Module#prepend`) | Structural changes to existing PallasTrade classes |
| 2 | **Dependency Injection** (`PallasTrade.dependencies`) | Swapping how a core service computes |
| 3 | **Event Subscriber** | Side effects — always prefer over `after_save` callbacks |
| 4 | **Direct modification** | Acceptable; add comment: `# PALLAS-CUSTOM: <reason>` |

Direct gem modifications MUST include a corresponding spec in `backend/spec/`.
```

**验证**：
```bash
grep -n "不要修改.*源码\|do not modify.*source\|don't modify.*gem" backend/CLAUDE.md
# 预期输出：空（零匹配）
```

**产出物**：`backend/CLAUDE.md`（已修正）

---

#### 子步骤 1.3：修正 `platform/AGENTS.md` 和 `storefront/AGENTS.md`（30 分钟）

**涉及文件**：
- `d:\pallastrade\platform\AGENTS.md`
- `d:\pallastrade\storefront\AGENTS.md`

**操作**：两个文件都有一段名为 "Governance Documents" 的表格，其中引用了 5 个不存在的文件。找到该表格，删除以下 5 行：

```
| `../docs/governance/rename-map.yml` | ... |
| `../docs/governance/OBLIGATIONS.md` | ... |
| `../docs/governance/IMPACT_MAP.md` | ... |
| `../docs/governance/PAYMENT_SECURITY_GATE.md` | ... |
| `../docs/adr/` | ... |
```

**替换为**：
```markdown
| `../AGENTS.md` | Root agent instructions — single source of truth for all components |
```

**验证**：
```bash
grep -n "rename-map.yml\|OBLIGATIONS.md\|IMPACT_MAP.md\|PAYMENT_SECURITY_GATE.md\|docs/adr" platform/AGENTS.md storefront/AGENTS.md
# 预期输出：空
```

**产出物**：`platform/AGENTS.md`、`storefront/AGENTS.md`（已修正）

---

#### 子步骤 1.4：修正 `/pallastrade:doctor` 路径探测（1.5 小时）

**涉及文件**：`d:\pallastrade\ai\commands\doctor.md`

**操作**：找到 compose 文件路径探测的描述（搜索关键词 `docker-compose`），修改探测优先级为：

```
1. backend/docker-compose.dev.yml   ← 当前实际位置（优先）
2. backend/docker-compose.yml        ← fallback
3. docker-compose.yml                ← 根目录（保留兼容，但放最后）
```

同时检查 `doctor.md` 中是否有其他路径引用（如 `server/`）需要同步修正。

**产出物**：`ai/commands/doctor.md`（已修正）

---

#### 子步骤 1.5：创建根 `AGENTS.md`（4 小时，**最重要的一步**）

**新建文件**：`d:\pallastrade\AGENTS.md`

这是整个 Harness 体系的**宪法文件**。AI 从根目录启动时读到的第一份信息。以下是完整模板，你需要根据项目实际情况微调 `【】` 标注的部分。

```markdown
# PallasTrade — Agent Instructions (Root)

You are working on **PallasTrade Commerce**, a self-hosted e-commerce platform
built on Ruby on Rails. This is a monorepo. This file is the single source of
truth for all AI agents. Component-level files supplement it.

---

## 1. Repository Layout

| Directory | Purpose | Can Modify? |
|---|---|---|
| `backend/` | Rails application root | — |
| `backend/app/` | Customer application code (models, controllers, decorators, subscribers) | ✅ Yes, freely |
| `backend/pallastrade_gems/` | Owned framework source — 13 local gems | ⚠️ Prefer Decorator/DI first. Direct changes OK with `# PALLAS-CUSTOM:` comment |
| `backend/db/migrate/` | Past database migrations | 🚫 Never modify. Create a NEW migration instead |
| `backend/db/schema.rb` | Auto-generated schema snapshot | 🚫 Never hand-edit |
| `backend/Gemfile.lock` | Auto-generated dependency lock | 🚫 Never hand-edit |
| `storefront/` | Next.js customer-facing storefront | — |
| `storefront/src/` | Storefront source code | ✅ Yes, freely |
| `platform/` | TypeScript monorepo (packages) | — |
| `platform/packages/sdk/` | `@pallastrade/sdk` — Store API client | ✅ Yes |
| `platform/packages/admin-sdk/` | `@pallastrade/admin-sdk` — Admin API client | ✅ Yes |
| `platform/packages/cli/` | `@pallastrade/cli` — Project management CLI | ✅ Yes |
| `platform/packages/dashboard/` | `@pallastrade/dashboard` — React SPA admin | ✅ Yes |
| `platform/packages/dashboard-ui/` | `@pallastrade/dashboard-ui` — Design system | ✅ Yes |
| `platform/packages/dashboard-core/` | `@pallastrade/dashboard-core` — Plugin framework | ✅ Yes |
| `ai/` | Agent skills and safety hooks | — |
| `ai/skills/` | 24 domain-specific SKILL.md files | ✅ Yes, update as code evolves |
| `ai/hooks/` | Safety hooks (bash scripts) | ⚠️ Understand full impact before modifying |
| `.github/workflows/` | GitHub Actions CI definitions | ⚠️ Understand full impact before modifying |
| `harness/` | Engineering policies and configs | ✅ Yes (active construction zone) |
| `scripts/harness/` | Harness CLI Node.js source | ✅ Yes (active construction zone) |

---

## 2. Before Writing Any Code

1. **Read the root AGENTS.md first.** You are doing that now.
2. **Read the relevant Skill file.** Map task domain → `ai/skills/<domain>/SKILL.md`.
   Use `pallastrade-customization` FIRST when the right customization approach isn't obvious.
3. **Run `harness affected`** to see what your change will impact.
4. **Check the anti-patterns list (§5).** Know what NOT to do before you start.

---

## 3. Customization Decision Tree (MUST follow this order)

Lower number = safer upgrade, cleaner code, easier to test.

| Priority | Approach | When to Use | Deep-Dive Skill |
|---|---|---|---|
| 1 | **Settings / `PallasTrade::Config`** | Toggle behavior at runtime | (straightforward) |
| 2 | **Events + Subscribers** | Side effects: sync to ERP, send notifications, update caches | `pallastrade-events-webhooks` |
| 3 | **Dependency Injection** (`PallasTrade.dependencies`) | Swap how a core service computes (cart, tax, search, checkout) | `pallastrade-dependencies` |
| 4 | **Admin Extensions / Ransack** | Customize admin UI, sidebar, tables, search | `pallastrade-admin` / `pallastrade-api-v3` |
| 5 | **Generators** (`pallastrade:api_resource` / `pallastrade:model`) | Brand-new model + API endpoint | `pallastrade-resource` |
| 6 | **Decorators** (`Module#prepend`) | Structural changes to existing PallasTrade classes | `pallastrade-decorators` |
| 7 | **Extensions (gems)** | Share customization across multiple PallasTrade apps | `pallastrade-extensions` |

**If you skip to a lower number without trying higher ones, your PR will be flagged.**

---

## 4. API v3 Rules (NEVER violate)

- All API routes under `/api/v3/store/` (customer) or `/api/v3/admin/` (admin)
- All IDs in API responses are **prefixed**: `prod_xxx`, `order_xxx`, `variant_xxx`, `brand_xxx`, etc.
- Never expose raw integer primary keys in any API response body
- Always scope queries through `current_store`:
  ```ruby
  current_store.products.where(active: true)  # ✅ Correct
  PallasTrade::Product.where(active: true)     # 🚫 Cross-store data leak
  ```
- List endpoints return `{ data: [...], meta: { count, current_page, total_pages } }`
- Single-resource endpoints return `{ data: { id, type, attributes } }`
- Use `expand=...` for sideloading, `fields=...` for sparse fieldsets
- Auth: Store API = publishable key (`pk_...`), Admin API = secret key (`sk_...`) or JWT

---

## 5. Anti-Patterns (BLOCKED by CI — not just "suggested")

| # | NEVER do this | Do this instead | CI Rule |
|---|---|---|---|
| AP-001 | `style={{ }}` inline styles in JSX/TSX | Use Tailwind classes (`className="..."`) or design-system component props | `anti-patterns.json` AP-001 |
| AP-002 | `fetch('/api/v3/...')` raw HTTP calls | Use `@pallastrade/sdk` (Store) or `@pallastrade/admin-sdk` (Admin) typed client | AP-002 |
| AP-003 | `Model.create(...)` outside `spec/` files | Use Factory Bot in tests, Service objects in application code | AP-003 |
| AP-004 | `after_save :do_something` callbacks | Create a `PallasTrade::Subscriber` subclass and register it | AP-004 |
| AP-005 | `PallasTrade::Order.all` without store scope | Always chain from `current_store`: `current_store.orders` | AP-005 |
| AP-006 | Hardcoded hex colors (`#ff0000`) in components | Use CSS custom properties from design tokens (`var(--color-brand-primary)`) | AP-006 |
| AP-007 | Hand-editing auto-generated files | Run the generation command, then commit the result | `generated:check` |

---

## 6. Minimum Verification Per Change Type

| What you changed | Minimum check | Estimated Time |
|---|---|---|
| Any Ruby file | `harness check --profile quick` | ≤5 min |
| Model / DB schema / migration | + `harness check --profile full` | ≤45 min |
| API endpoint (new/modified) | + `harness generated:check` (OpenAPI + SDK types) | ≤5 min |
| UI component / style | + `harness e2e dashboard` or `harness e2e storefront` | ≤15 min |
| Payment logic | + payment sandbox gate | ≤30 min |
| AI Skill file (`ai/skills/`) | + `harness eval ai --check-freshness` | ≤2 min |
| Framework version upgrade | + `harness upgrade:audit` + `harness upgrade:verify` | ≤20 min |
| Any change | `harness doc-impact --base origin/main` — checks knowledge docs are synced | ≤1 min |

---

## 7. Knowledge Sync Rules — Code Changed = Docs MUST Sync

**When your PR changes files matching the left column, it MUST also update
the corresponding docs in the right column. CI enforces this.**

| Code Change (Glob) | Knowledge Docs That MUST Be Updated |
|---|---|
| `backend/app/models/**/*.rb` (new/modified) | `ai/skills/pallastrade-catalog/SKILL.md` or `pallastrade-data-model/SKILL.md` |
| `backend/app/controllers/**/api/v3/**/*.rb` (new/modified) | `ai/skills/pallastrade-api-v3/SKILL.md` + `platform/docs/store.yaml` or `admin.yaml` |
| `backend/app/decorators/**/*.rb` (new/modified) | `ai/skills/pallastrade-decorators/SKILL.md` + relevant domain skill |
| `backend/app/subscribers/**/*.rb` (new/modified) | `ai/skills/pallastrade-events-webhooks/SKILL.md` |
| `storefront/src/components/**/*.tsx` (new/modified) | `ai/skills/pallastrade-storefront/SKILL.md` §Components |
| `storefront/src/app/**/*.tsx` (new page/route) | `ai/skills/pallastrade-storefront/SKILL.md` + E2E test |
| `*.css` / `tailwind.config.*` (modified) | `ai/skills/pallastrade-storefront/SKILL.md` §Style Guide or `pallastrade-admin/SKILL.md` §Styling |
| `platform/packages/dashboard-ui/**/*.tsx` (modified) | Component documentation + Storybook story (if applicable) |
| `ai/skills/**/SKILL.md` (modified) | `harness/scenarios/scenarios.json` — add/update an Eval Scenario |
| `harness/policies/anti-patterns.json` (modified) | This `AGENTS.md` §5 — ensure the anti-pattern table matches |
| `AGENTS.md` / `CLAUDE.md` (modified) | Run `harness docs:check` to verify no broken references |
| Any file (framework version upgrade) | ALL Skill files — `harness eval ai --check-freshness` |

**CI command**: `harness doc-impact --base origin/main` checks your PR against this table.
If any required doc update is missing, the PR is blocked with status `docs-required`.

---

## 8. Dangerous Operations (PHYSICALLY BLOCKED)

These commands are intercepted by safety hooks at the tool-call level,
not the prompt level. The AI literally cannot execute them.

- `rake db:drop` / `rails db:drop` / `rake db:reset` / `rails db:reset`
- `DROP TABLE pallastrade_*` / `DROP DATABASE`
- `DELETE FROM pallastrade_orders` (and similar mass deletes on core tables)
- `PallasTrade::Order.delete_all` / `PallasTrade::Order.destroy_all`
- `git push --force origin main` / `git push --force origin master`
- Writing secrets (`sk_live_...`, `AKIA...`, `ghp_...`) into source files

**Bypass**: Set `PALLASTRADE_HOOKS_DISABLE=1` and run the command manually in a terminal
(not through the AI tool invocation). This is for emergencies only.
```

**产出物**：`AGENTS.md`（根目录，新建）

**验证**：用 AI 测试——打开新会话，让 AI 从根目录启动，问它"这个项目有哪些目录、各自我能改吗？"如果 AI 的回答与 AGENTS.md 一致，说明文件生效。

---

#### 子步骤 1.6：清理 `.vscode/tasks.json`（1 小时）

**涉及文件**：`d:\pallastrade\.vscode\tasks.json`

**操作**：不逐一手工修改 119 个任务，而是**直接覆盖**为以下精简版（6 个任务）：

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Harness: Doctor",
      "type": "shell",
      "command": "node scripts/harness/cli.mjs doctor",
      "group": "test",
      "presentation": { "reveal": "always", "panel": "dedicated" }
    },
    {
      "label": "Harness: Quick Check",
      "type": "shell",
      "command": "node scripts/harness/cli.mjs check --profile quick",
      "group": "test"
    },
    {
      "label": "Harness: Full Check",
      "type": "shell",
      "command": "node scripts/harness/cli.mjs check --profile full",
      "group": "test"
    },
    {
      "label": "Harness: E2E Dashboard",
      "type": "shell",
      "command": "node scripts/harness/cli.mjs e2e dashboard"
    },
    {
      "label": "Harness: E2E Storefront",
      "type": "shell",
      "command": "node scripts/harness/cli.mjs e2e storefront"
    },
    {
      "label": "Harness: Generated Check",
      "type": "shell",
      "command": "node scripts/harness/cli.mjs generated:check"
    }
  ]
}
```

**旧文件处理**：将原 `tasks.json` 备份为 `tasks.json.backup`，保留一周后删除。

**验证**：
```bash
grep "D:\\\\pallastrade" .vscode/tasks.json
# 预期输出：空（零匹配——无绝对路径）
```

---

#### 子步骤 1.7：修正 Lefthook glob（30 分钟）

**涉及文件**：`d:\pallastrade\platform\lefthook.yml`（如果存在）

**操作**：搜索 `pallastrade/api/app/serializers`，替换为 `backend/pallastrade_gems/pallastrade_api/app/serializers`。如果该 hook 已不再需要，直接移除整个 hook 定义。

**验证**：
```bash
cd d:\pallastrade\platform
npx lefthook run pre-commit --dry-run 2>&1 | grep -i "error\|not found"
# 预期输出：空（无报错）
```

---

#### 第 1 步知识同步清单

本次修改涉及以下知识文档，必须随代码一起更新：

| 文件 | 操作 | 状态 |
|---|---|---|
| `AGENTS.md`（根） | 新建 | ✅ |
| `platform/CLAUDE.md` | 修正路径 | ✅ |
| `backend/CLAUDE.md` | 修正修改策略 | ✅ |
| `platform/AGENTS.md` | 删除失效引用 | ✅ |
| `storefront/AGENTS.md` | 删除失效引用 | ✅ |
| `ai/commands/doctor.md` | 修正路径 | ✅ |
| `.vscode/tasks.json` | 重写 | ✅ |

#### 第 1 步完成验收

```bash
# 1. 旧路径零残留
grep -rn "pallastrade/core" platform/CLAUDE.md        # → 空
grep -rn "不要修改.*源码" backend/CLAUDE.md            # → 空
grep -rn "rename-map.yml" platform/AGENTS.md           # → 空

# 2. VS Code 任务无绝对路径
grep "D:\\\\pallastrade" .vscode/tasks.json            # → 空

# 3. 根 AGENTS.md 存在且包含关键章节
grep -c "Decision Tree" AGENTS.md                      # → ≥1
grep -c "Knowledge Sync Rules" AGENTS.md               # → ≥1
grep -c "Anti-Patterns" AGENTS.md                      # → ≥1

# 4. Lefthook 无报错
cd platform && npx lefthook run pre-commit --dry-run   # → 无 error
```

---

### 第 2 步：让验证真正跑起来

**总耗时**：8-12 天（约 55-80 小时）
**前置条件**：第 1 步全部完成
**目标**：全量测试接入 CI + 覆盖率门禁 + 反模式扫描 + 知识同步检查

---

#### 子步骤 2.1：创建 Harness CLI 骨架（1 天）

**新建文件 1**：`d:\pallastrade\package.json`
```json
{
  "name": "pallastrade-monorepo",
  "private": true,
  "type": "module",
  "engines": { "node": ">=22.0.0" },
  "scripts": {
    "harness": "node scripts/harness/cli.mjs"
  }
}
```

**新建目录**：`d:\pallastrade\scripts\harness\`

**新建文件 2**：`d:\pallastrade\scripts\harness\cli.mjs`
```javascript
#!/usr/bin/env node
import { existsSync, readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync } from 'node:child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..', '..');

const args = process.argv.slice(2);
const cmd = args[0];

function getProfile(args) {
  const idx = args.indexOf('--profile');
  return idx >= 0 ? args[idx + 1] : 'quick';
}

if (cmd === 'doctor') {
  // ---- doctor ----
  const checks = [
    ['git-repo', () => { execSync('git rev-parse --git-dir', { cwd: ROOT, stdio: 'pipe' }); return true; }],
    ['node-version', () => parseInt(process.version.slice(1)) >= 22],
    ['dir-backend', () => existsSync(resolve(ROOT, 'backend'))],
    ['dir-platform', () => existsSync(resolve(ROOT, 'platform'))],
    ['dir-storefront', () => existsSync(resolve(ROOT, 'storefront'))],
    ['dir-ai', () => existsSync(resolve(ROOT, 'ai'))],
    ['agents-md', () => existsSync(resolve(ROOT, 'AGENTS.md'))],
    ['vscode-tasks', () => {
      const p = resolve(ROOT, '.vscode', 'tasks.json');
      if (!existsSync(p)) return true;
      const content = readFileSync(p, 'utf-8');
      return !content.includes('D:\\\\') && !content.includes('D:/');
    }],
  ];

  let passed = 0;
  for (const [name, fn] of checks) {
    try {
      const ok = fn();
      console.log(`${ok ? '✅' : '❌'} ${name}`);
      if (ok) passed++;
    } catch (e) {
      console.log(`❌ ${name}: ${e.message}`);
    }
  }
  console.log(`\n${passed}/${checks.length} checks passed`);

} else if (cmd === 'affected') {
  // ---- affected (stub) ----
  const base = args.includes('--base') ? args[args.indexOf('--base') + 1] : 'origin/main';
  try {
    const changed = execSync(`git diff --name-only ${base}...HEAD`, { cwd: ROOT, encoding: 'utf-8' });
    const files = changed.trim().split('\n').filter(Boolean);
    const components = new Set();
    for (const f of files) {
      if (f.startsWith('backend/')) components.add('backend');
      else if (f.startsWith('platform/')) components.add('platform');
      else if (f.startsWith('storefront/')) components.add('storefront');
      else if (f.startsWith('ai/')) components.add('ai');
    }
    console.log(JSON.stringify({
      filesChanged: files.length,
      affectedComponents: [...components],
      estimatedTests: files.length * 3,
    }));
  } catch { console.log('{"filesChanged":0,"affectedComponents":[],"estimatedTests":0}'); }

} else if (cmd === 'check') {
  // ---- check (stub — will grow in sub-steps 2.2-2.6) ----
  const profile = getProfile(args);
  console.log(`[harness] check --profile ${profile}`);
  console.log('[harness] (stub — CI workflows handle actual execution)');
  console.log('[harness] Use GitHub Actions for full profile execution.');

} else if (cmd === 'doc-impact') {
  // ---- doc-impact (sub-step 2.7) ----
  await import('./doc-impact.mjs').then(m => m.run({ rootDir: ROOT, args }));

} else if (cmd === 'e2e') {
  // ---- e2e ----
  const target = args[1];
  console.log(`[harness] e2e ${target} (stub — CI handles actual execution)`);

} else {
  console.log(`Usage: node scripts/harness/cli.mjs <doctor|check|affected|doc-impact|e2e|eval-ai|generated:check>`);
}
```

**验证**：
```powershell
cd d:\pallastrade
node scripts/harness/cli.mjs doctor
# 预期输出：至少 6/8 checks passed（vscode-tasks 取决于子步骤 1.6 是否完成）
```

---

#### 子步骤 2.2：Dashboard E2E 接入 CI（2-3 天，**最易踩坑**）

**目标**：让 Dashboard 现有的 34 个 Playwright E2E 测试在 GitHub Actions 中自动执行。

**为什么这个子步骤最耗时**：Playwright 在 CI 中需要 PostgreSQL + Redis + Rails 后端全部启动。每个服务的配置、启动顺序、健康检查都可能出问题。每轮调试需要等 CI 跑完（5-10 分钟）。

**策略**：先跑通 1 个 smoke test，再逐步放开全部 34 个。

**操作序列**：

**2.2a**：先在 Dashboard E2E 中创建一个最小 smoke test（如果不存在）：
```typescript
// platform/packages/dashboard/e2e/smoke.spec.ts
import { test, expect } from '@playwright/test';

test('admin login page loads @smoke', async ({ page }) => {
  await page.goto('/admin/login');
  await expect(page.locator('input[type="email"]')).toBeVisible();
});
```

**2.2b**：在根级 CI 中新增一个 Job。修改或新建 `.github/workflows/harness-full.yml`：

```yaml
name: Harness Full
on:
  pull_request:
    types: [opened, synchronize, reopened]
    branches: [main]

jobs:
  # ... (其他 job 在后面子步骤中添加)

  e2e-dashboard:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: pallastrade
          POSTGRES_PASSWORD: password
        options: >-
          --health-cmd pg_isready --health-interval 10s --health-timeout 5s --health-retries 5
        ports: [5432:5432]
      redis:
        image: redis:7
        options: >-
          --health-cmd "redis-cli ping" --health-interval 10s --health-timeout 5s --health-retries 5
        ports: [6379:6379]

    steps:
      - uses: actions/checkout@v4

      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '.ruby-version'
          bundler-cache: true
          working-directory: backend

      - name: Setup Node
        uses: actions/setup-node@v4
        with: { node-version: '22' }

      - name: Setup pnpm
        uses: pnpm/action-setup@v4
        with: { version: 11.1.1 }

      - name: Setup Database
        run: |
          cd backend
          cp .env.example .env
          bundle exec rails db:create db:migrate db:seed

      - name: Start Rails Server
        run: |
          cd backend
          bundle exec rails server -p 3000 -e test &
          # Wait for server to be ready
          for i in $(seq 1 30); do
            curl -s http://localhost:3000/up && break
            sleep 2
          done

      - name: Install Playwright Browsers
        run: |
          cd platform/packages/dashboard
          pnpm install
          npx playwright install --with-deps chromium

      - name: Run E2E (smoke first)
        run: |
          cd platform/packages/dashboard
          npx playwright test --grep "@smoke" --reporter=html
        env:
          PLAYWRIGHT_BASE_URL: http://localhost:3000

      - name: Upload Report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: playwright-report-dashboard
          path: platform/packages/dashboard/playwright-report/
```

**2.2c**：push 到 GitHub → 观察 CI 日志 → 根据报错调整。常见问题：

| 症状 | 可能原因 | 解决 |
|---|---|---|
| `pg_isready: not found` | Postgres 镜像版本问题 | 改用 `pg_isready` 的正确路径或换镜像 tag |
| Rails 启动后 `curl` 超时 | `db:seed` 失败或 `.env` 缺少必要变量 | 检查 CI 日志中的 Rails 启动输出 |
| Playwright 报 `ECONNREFUSED` | Rails 在 0.0.0.0 而不是 localhost 监听 | `-b 0.0.0.0` |
| Playwright 找不到浏览器 | `playwright install` 未执行 | 确认 `--with-deps` 参数 |

**2.2d**：smoke test 通过后，去掉 `--grep "@smoke"` 限制，跑全量 34 个。如果全量超时（30min），拆分为多个 shard 或用 `--workers` 限制并发数。

**产出物**：`.github/workflows/harness-full.yml` 中的 `e2e-dashboard` job 在 CI 中全绿

---

#### 子步骤 2.3：Storefront E2E 接入 CI（1 天）

**参考 2.2 的模式**。Storefront E2E 更简单——它可能不需要完整的 Backend 后端（取决于现有 E2E 是 mock 模式还是真实 API 模式）。

```yaml
  e2e-storefront:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '22' }
      - uses: pnpm/action-setup@v4
        with: { version: 11.1.1 }
      - name: Install & Run E2E
        run: |
          cd storefront
          pnpm install
          npx playwright install --with-deps chromium
          pnpm test:e2e
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: playwright-report-storefront
          path: storefront/playwright-report/
```

---

#### 子步骤 2.4：全量 Backend + Platform 测试接入 CI（2 天）

**2.4a**：Backend RSpec 改为扫描所有 Gem 的 spec 目录。

在 `harness-full.yml` 中：
```yaml
  test-backend:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    services:
      postgres: # ... (同 2.2)
      redis: # ...

    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with: { ruby-version: '.ruby-version', bundler-cache: true, working-directory: backend }
      - name: Setup DB
        run: |
          cd backend
          cp .env.example .env
          bundle exec rails db:create db:migrate
      - name: Run All RSpec
        run: |
          cd backend
          bundle exec rspec spec/ pallastrade_gems/pallastrade_*/spec/ \
            --format progress \
            --format RspecJunitFormatter --out rspec-junit.xml
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: rspec-junit, path: backend/rspec-junit.xml }
```

**2.4b**：Platform 支付 spec。如果 `platform/payments/` 下是独立的 Ruby 项目：
```yaml
  test-platform-payments:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with: { ruby-version: '.ruby-version', bundler-cache: true, working-directory: platform/payments }
      - name: Run Payment Specs
        run: |
          cd platform/payments
          bundle exec rspec --format RspecJunitFormatter --out rspec-junit.xml
```

**2.4c**：SDK Integration：
```yaml
  test-sdk-integration:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with: { version: 11.1.1 }
      - name: Run Integration Tests
        run: |
          cd platform
          pnpm install
          pnpm --filter @pallastrade/sdk test:integration
```

**产出物**：`harness check --profile full` 在 CI 中包含了所有上述测试

---

#### 子步骤 2.5：建立覆盖率门禁（1.5 天）

**2.5a**：Ruby SimpleCov 配置。

修改 `backend/Gemfile`，在 `:test` group 中确保：
```ruby
group :test do
  gem 'simplecov', require: false
  gem 'simplecov-cobertura', require: false
end
```

修改 `backend/spec/spec_helper.rb`（或 `rails_helper.rb`），在文件顶部：
```ruby
require 'simplecov'
require 'simplecov-cobertura'

SimpleCov.start 'rails' do
  enable_coverage :branch
  minimum_coverage line: 80, branch: 60

  add_group 'Application', 'app/'
  add_group 'Gems', 'pallastrade_gems/'
  add_filter '/spec/'
  add_filter '/config/'

  formatter SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::CoberturaFormatter,
  ])
end
```

`bundle install` 然后跑一次 `bundle exec rspec`，确认 `coverage/` 目录生成了报告。

**2.5b**：Vitest 覆盖率配置。

在各包的 `vitest.config.ts` 中增加：
```typescript
export default defineConfig({
  test: {
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html', 'cobertura'],
      thresholds: {
        lines: 70,   // 默认值，SDK 包覆盖为 90
        branches: 60,
      },
    },
  },
});
```

`@pallastrade/sdk` 的配置中把 `thresholds.lines` 改为 90。

**2.5c**：CI 中覆盖率低于阈值时 RSpec/Vitest 会以非零退出码结束，CI 自动失败。

---

#### 子步骤 2.6：反模式扫描 + AI Freshness + 生成物漂移（2 天）

**2.6a**：创建反模式规则文件。

**新建文件**：`d:\pallastrade\harness\policies\anti-patterns.json`
```json
{
  "schemaVersion": 1,
  "rules": [
    {
      "id": "AP-001",
      "name": "inline-style",
      "severity": "error",
      "pattern": "style=\\{?\\{",
      "fileGlob": "storefront/src/**/*.tsx",
      "message": "Inline style detected. Use Tailwind className or design-system component props."
    },
    {
      "id": "AP-002",
      "name": "raw-fetch-api",
      "severity": "error",
      "pattern": "fetch\\s*\\(\\s*['\"`].*\\/api\\/v3\\/",
      "fileGlob": "{storefront/src,platform/packages}/**/*.{ts,tsx}",
      "excludeGlob": "**/sdk/**",
      "message": "Raw fetch to PallasTrade API. Use @pallastrade/sdk or @pallastrade/admin-sdk."
    },
    {
      "id": "AP-003",
      "name": "model-create-outside-test",
      "severity": "warning",
      "pattern": "\\.(create!?|save!)\\s*[\\(\\{]",
      "fileGlob": "backend/app/**/*.rb",
      "excludeGlob": "**/spec/**",
      "message": "Model.create/save outside spec. Use Factory Bot in tests, Service in app."
    },
    {
      "id": "AP-004",
      "name": "after-save-callback",
      "severity": "warning",
      "pattern": "after_save\\s+:",
      "fileGlob": "backend/app/**/*.rb",
      "message": "after_save callback used. Consider PallasTrade::Subscriber for side effects."
    },
    {
      "id": "AP-005",
      "name": "unscoped-store-query",
      "severity": "error",
      "pattern": "PallasTrade::(Order|Product|User|Payment)\\s*\\.\\s*(all|where|find_by)",
      "fileGlob": "backend/app/**/*.rb",
      "excludeGlob": "**/spec/**",
      "message": "Unscoped query. Always scope through current_store."
    }
  ]
}
```

**新建扫描脚本**：`d:\pallastrade\scripts\harness\scan-anti-patterns.mjs`

```javascript
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { globSync } from 'glob';

export function scan({ rootDir }) {
  const rulesPath = resolve(rootDir, 'harness', 'policies', 'anti-patterns.json');
  const rules = JSON.parse(readFileSync(rulesPath, 'utf-8')).rules;
  let totalViolations = 0;

  for (const rule of rules) {
    const files = globSync(rule.fileGlob, { cwd: rootDir, ignore: rule.excludeGlob ? [rule.excludeGlob] : [] });
    for (const file of files) {
      const content = readFileSync(resolve(rootDir, file), 'utf-8');
      const regex = new RegExp(rule.pattern, 'gm');
      const matches = content.match(regex);
      if (matches) {
        for (const match of matches) {
          console.log(`❌ ${rule.id} [${rule.severity}] ${file}: ${rule.message}`);
          console.log(`   matched: ${match.trim().slice(0, 80)}`);
          totalViolations++;
        }
      }
    }
  }

  if (totalViolations > 0) {
    console.log(`\n${totalViolations} anti-pattern violation(s) found.`);
    const errors = rules.filter(r => r.severity === 'error');
    if (errors.length > 0) process.exit(1);
  } else {
    console.log('✅ No anti-patterns detected.');
  }
}

// CLI entry
if (process.argv[1] && import.meta.url.endsWith(process.argv[1].replace(/\\/g, '/'))) {
  const rootDir = resolve(import.meta.dirname, '..', '..');
  scan({ rootDir });
}
```

在 `harness-full.yml` 中增加：
```yaml
  anti-pattern-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '22' }
      - run: node scripts/harness/scan-anti-patterns.mjs
```

**2.6b**：AI Freshness Check。

**新建文件**：`d:\pallastrade\scripts\harness\eval-ai.mjs`

```javascript
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

export function checkFreshness({ rootDir }) {
  const skillDir = resolve(rootDir, 'ai', 'skills');
  const skills = readdirSync(skillDir, { withFileTypes: true })
    .filter(d => d.isDirectory())
    .map(d => d.name);

  let errors = 0;

  for (const skill of skills) {
    const skillFile = join(skillDir, skill, 'SKILL.md');
    if (!existsSync(skillFile)) continue;
    const content = readFileSync(skillFile, 'utf-8');

    // Extract path references in backticks
    const pathRefs = content.matchAll(/`([a-z_]+\/[a-z0-9_\/\.\-]+)`/gi);
    for (const m of pathRefs) {
      const p = resolve(rootDir, m[1]);
      if (m[1].includes('/') && !existsSync(p)) {
        console.log(`❌ ${skill}/SKILL.md: path not found: ${m[1]}`);
        errors++;
      }
    }

    // Extract CLI commands
    const cmdRefs = content.matchAll(/`pallastrade\s+([a-z_:]+)`/gi);
    // ... validate against known commands
  }

  if (errors > 0) {
    console.log(`\n❌ ${errors} freshness error(s).`);
    process.exit(1);
  }
  console.log(`✅ ${skills.length} skills checked, 0 errors.`);
}
```

**2.6c**：生成物漂移检查。

**新建文件**：`d:\pallastrade\scripts\harness\generated-check.mjs`
```javascript
import { execSync } from 'node:child_process';
import { resolve } from 'node:path';

export function check({ rootDir }) {
  // Regenerate all auto-generated files
  const cmds = [
    ['OpenAPI types', 'cd platform && pnpm --filter @pallastrade/sdk generate:types'],
    ['CLI admin spec', 'cd platform && pnpm --filter @pallastrade/cli generate:admin-spec'],
  ];

  for (const [name, cmd] of cmds) {
    try {
      execSync(cmd, { cwd: rootDir, stdio: 'pipe' });
    } catch (e) {
      console.error(`❌ ${name}: generation failed`);
      process.exit(1);
    }
  }

  // Check for uncommitted changes
  try {
    execSync('git diff --exit-code', { cwd: rootDir, stdio: 'pipe' });
    console.log('✅ generated:check — no drift');
  } catch {
    console.error('❌ generated:check — drift detected. Regenerate and commit.');
    process.exit(1);
  }
}
```

---

#### 子步骤 2.7：实现 `harness doc-impact` 知识同步检查（1.5 天）

**新建文件**：`d:\pallastrade\scripts\harness\doc-impact.mjs`

核心逻辑：
1. 读取 `AGENTS.md` §7 的知识同步规则表
2. 获取当前 PR 的文件变更列表（`git diff --name-only origin/main...HEAD`）
3. 逐文件逐规则匹配：变更了代码 X → 需要更新文档 Y
4. 检查文档 Y 是否在本次 PR 的变更列表中
5. 输出缺失清单；如有缺失 → CI 失败

```javascript
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { execSync } from 'node:child_process';

// Knowledge sync rules — mirrors AGENTS.md §7
const SYNC_RULES = [
  {
    codeGlob: /^backend\/app\/models\/.*\.rb$/,
    docs: ['ai/skills/pallastrade-catalog/SKILL.md', 'ai/skills/pallastrade-data-model/SKILL.md'],
    anyOf: true,
  },
  {
    codeGlob: /^backend\/app\/controllers\/.*\/api\/v3\/.*\.rb$/,
    docs: ['ai/skills/pallastrade-api-v3/SKILL.md', 'platform/docs/store.yaml', 'platform/docs/admin.yaml'],
    anyOf: false, // all required
  },
  {
    codeGlob: /^storefront\/src\/components\/.*\.tsx$/,
    docs: ['ai/skills/pallastrade-storefront/SKILL.md'],
  },
  {
    codeGlob: /\.(css|scss)$|tailwind\.config\./,
    docs: ['ai/skills/pallastrade-storefront/SKILL.md', 'ai/skills/pallastrade-admin/SKILL.md'],
    anyOf: true,
  },
  {
    codeGlob: /^ai\/skills\/.*\/SKILL\.md$/,
    docs: ['harness/scenarios/scenarios.json'],
  },
];

export async function run({ rootDir, args }) {
  const base = args.includes('--base') ? args[args.indexOf('--base') + 1] : 'origin/main';
  const changedFiles = execSync(`git diff --name-only ${base}...HEAD`, { cwd: rootDir, encoding: 'utf-8' })
    .trim().split('\n').filter(Boolean);

  const requiredDocs = new Set();
  for (const rule of SYNC_RULES) {
    const matchedFiles = changedFiles.filter(f => rule.codeGlob.test(f));
    if (matchedFiles.length > 0) {
      for (const doc of rule.docs) {
        requiredDocs.add(doc);
      }
    }
  }

  const missingDocs = [];
  for (const doc of requiredDocs) {
    if (!changedFiles.includes(doc) && !existsSync(resolve(rootDir, doc))) {
      missingDocs.push(doc);
    }
  }

  console.log(`Changed files: ${changedFiles.length}`);
  console.log(`Required docs: ${requiredDocs.size}`);
  console.log(`Missing docs: ${missingDocs.length}`);

  if (missingDocs.length > 0) {
    console.log('\n📋 The following knowledge docs must be updated:');
    for (const doc of missingDocs) {
      console.log(`  [ ] ${doc}`);
    }
    console.log('\n❌ PR blocked: docs-required');
    process.exit(1);
  }

  console.log('✅ All required knowledge docs are synced.');
}
```

在 `harness-full.yml` 中增加：
```yaml
  doc-impact:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: actions/setup-node@v4
        with: { node-version: '22' }
      - run: node scripts/harness/cli.mjs doc-impact --base origin/main
```

---

#### 第 2 步知识同步清单

| 本次变更 | 需同步的知识文档 |
|---|---|
| 新增 `scripts/harness/cli.mjs` | `AGENTS.md`（已在第 1 步创建） |
| 新增 CI workflow Job | `AGENTS.md` §6 更新 CI profile 说明 |
| 新增 `anti-patterns.json` | `AGENTS.md` §5 确保表格一致 |
| 新增 `doc-impact.mjs` | `AGENTS.md` §7 确保规则表对应 |

#### 第 2 步完成验收

```bash
# 1. Dashboard E2E 在 CI 中全绿
#    → 检查 GitHub Actions 中 harness-full workflow 最新运行

# 2. 全量测试在 CI 中执行
#    → 查看 CI 日志，确认 RSpec 扫描了 pallastrade_gems/*/spec/

# 3. 覆盖率门禁生效
#    → 故意写一段无测试覆盖的代码，push PR → CI 应因覆盖率不足而失败

# 4. 反模式扫描生效
#    → 故意在 .tsx 文件中写 style={{ color: 'red' }} → CI 应报 AP-001

# 5. doc-impact 生效
#    → 新增一个 Model 但不同步更新对应 Skill → CI 应报告 docs-required

# 6. 生成物漂移检查生效
#    → 手改 SDK types 文件但不重新生成 → CI 应失败
```

---

### 第 3 步：让升级不再可怕

**总耗时**：3-5 天（约 20-35 小时）
**前置条件**：第 2 步全部完成（全量测试在 CI 中全绿）
**目标**：一键审计 + 升级前后对比 + 一键回滚 + 自动证据包

---

#### 子步骤 3.1：创建定制代码标记文件（1 小时）

**新建文件**：`d:\pallastrade\.pallastrade-customization`

```yaml
# PallasTrade Customization Manifest
# Lists all customer-owned code. Harness uses this to:
#   - Distinguish framework code from customer code during upgrades
#   - Prevent silent overwrites of customer files
#   - Generate upgrade impact reports

version: 1
customer: "Steven Bian (PallasTrade)"

# Directories that are entirely customer-owned
customization_roots:
  - "backend/app/"
  - "storefront/src/"

# Additional specific files that are customer-owned
extra_files:
  - "backend/config/initializers/pallastrade_custom.rb"

# Directories/files that are framework-managed (not customer-owned)
# These WILL be overwritten during upgrades — harness warns but does not block
framework_managed:
  - "backend/db/migrate/"
  - "backend/db/schema.rb"
  - "backend/Gemfile.lock"
  - "backend/pallastrade_gems/"
  - "storefront/pnpm-lock.yaml"
  - "platform/pnpm-lock.yaml"
```

---

#### 子步骤 3.2：实现 `upgrade:audit`（1.5 天）

**新建文件**：`d:\pallastrade\scripts\harness\upgrade-audit.mjs`

```javascript
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { globSync } from 'glob';
import { parse as parseYaml } from 'yaml';

export async function audit({ rootDir, from, to }) {
  // 1. Load customization manifest
  const manifest = parseYaml(readFileSync(resolve(rootDir, '.pallastrade-customization'), 'utf-8'));

  // 2. Load breaking changes for target version
  const bcFile = resolve(rootDir, 'harness', 'versions', `v${to}`, 'breaking-changes.json');
  if (!existsSync(bcFile)) {
    console.error(`No breaking changes file for v${to}. Create harness/versions/v${to}/breaking-changes.json first.`);
    process.exit(1);
  }
  const breakingChanges = JSON.parse(readFileSync(bcFile, 'utf-8'));

  // 3. Collect all customer files
  const customerFiles = [];
  for (const root of manifest.customization_roots) {
    customerFiles.push(...globSync(`${root}/**/*.rb`, { cwd: rootDir }));
  }
  if (manifest.extra_files) {
    customerFiles.push(...manifest.extra_files);
  }

  // 4. Scan each customer file against breaking changes
  const findings = [];
  for (const file of customerFiles) {
    const filePath = resolve(rootDir, file);
    if (!existsSync(filePath)) continue;
    const content = readFileSync(filePath, 'utf-8');

    for (const bc of breakingChanges) {
      const regex = new RegExp(bc.pattern, 'gm');
      const lines = content.split('\n');
      for (let i = 0; i < lines.length; i++) {
        if (regex.test(lines[i])) {
          findings.push({
            file,
            line: i + 1,
            severity: bc.severity || 'medium',
            breakingChange: bc.title,
            matchedCode: lines[i].trim().slice(0, 100),
            suggestedFix: bc.fix || 'Manual review required',
            skillReference: bc.skillRef || null,
          });
        }
      }
    }
  }

  // 5. Output report
  const report = {
    from, to,
    timestamp: new Date().toISOString(),
    customerFilesScanned: customerFiles.length,
    breakingChangesChecked: breakingChanges.length,
    impactedFiles: [...new Set(findings.map(f => f.file))].length,
    totalImpacts: findings.length,
    findings,
    recommendation: findings.filter(f => f.severity === 'critical').length > 0
      ? 'BLOCKED' : findings.length > 0 ? 'REVIEW_REQUIRED' : 'SAFE_TO_UPGRADE',
  };

  console.log(JSON.stringify(report, null, 2));

  // Exit non-zero if critical issues found
  if (report.recommendation === 'BLOCKED') process.exit(1);
}
```

**新建示例 breaking changes 文件**：`d:\pallastrade\harness\versions\v5.6\breaking-changes.json`
```json
[
  {
    "title": "Order#state renamed to Order#status",
    "pattern": "\\.state\\b",
    "severity": "high",
    "fix": "Replace all `order.state` with `order.status`",
    "skillRef": "pallastrade-checkout"
  },
  {
    "title": "Shipment model renamed to Fulfillment",
    "pattern": "PallasTrade::Shipment\\b",
    "severity": "high",
    "fix": "Replace PallasTrade::Shipment with PallasTrade::Fulfillment",
    "skillRef": "pallastrade-shipping-fulfillment"
  },
  {
    "title": "display_on column removed — use storefront_visible boolean",
    "pattern": "\\.display_on\\b",
    "severity": "medium",
    "fix": "Replace with .storefront_visible",
    "skillRef": "pallastrade-catalog"
  }
]
```

---

#### 子步骤 3.3：实现 `upgrade:baseline` + `upgrade:verify`（1 天）

**新建文件**：`d:\pallastrade\scripts\harness\upgrade-verify.mjs`

核心逻辑：
- `baseline --save`：运行 `harness check --profile full`，把输出的 JSON 保存到 `harness/baselines/baseline-{version}.json`
- `verify`：运行 `harness check --profile full`，与基线逐项对比

```javascript
import { execSync } from 'node:fs';
// ... (完整实现略 — 核心是 runFullProfile() → diff against baseline)
```

**验证**：
```bash
# 升级前
node scripts/harness/cli.mjs upgrade:baseline --save
# → baseline saved to harness/baselines/baseline-5.5.json

# 执行升级...

# 升级后
node scripts/harness/cli.mjs upgrade:verify
# → ✅ 1200/1200 pass (0 new failures) | Verdict: NO_REGRESSION
```

---

#### 子步骤 3.4：实现 `upgrade:rollback`（0.5 天）

**新建文件**：`d:\pallastrade\scripts\harness\upgrade-rollback.mjs`

```javascript
export async function rollback({ rootDir }) {
  // 1. Find pre-upgrade tag
  const tag = execSync('git tag --list "pre-upgrade-*" --sort=-creatordate | head -1',
    { cwd: rootDir, encoding: 'utf-8' }).trim();

  if (!tag) {
    console.error('No pre-upgrade tag found. Cannot rollback.');
    process.exit(1);
  }

  // 2. Git rollback
  console.log(`Rolling back to ${tag}...`);
  execSync(`git reset --hard ${tag}`, { cwd: rootDir, stdio: 'inherit' });

  // 3. DB rollback
  console.log('Rolling back database...');
  execSync('bundle exec rails db:migrate:down VERSION=<pre-upgrade-schema>',
    { cwd: resolve(rootDir, 'backend'), stdio: 'inherit' });

  // 4. Asset rebuild
  console.log('Rebuilding assets...');
  execSync('bundle exec rails assets:precompile',
    { cwd: resolve(rootDir, 'backend'), stdio: 'inherit' });

  // 5. Verify
  console.log('Verifying rollback...');
  execSync('node scripts/harness/cli.mjs check --profile quick',
    { cwd: rootDir, stdio: 'inherit' });

  console.log('✅ Rollback complete.');
}
```

---

#### 子步骤 3.5：实现 `upgrade:evidence`（0.5 天）

**新建文件**：`d:\pallastrade\scripts\harness\upgrade-evidence.mjs`

核心逻辑：
1. 收集 `upgrade:audit` 的 JSON 输出
2. 收集 `upgrade:verify` 的 JSON 输出
3. 收集 migration 日志
4. 生成 `upgrade-evidence-{from}-{to}.zip`

---

#### 第 3 步知识同步清单

| 本次变更 | 需同步的知识文档 |
|---|---|
| 新增 `.pallastrade-customization` | `AGENTS.md` §1 更新文件说明 |
| 新增 `harness/versions/` | `AGENTS.md` §7 更新知识同步规则 |
| 新增 upgrade 系列脚本 | `AGENTS.md` §6 更新验证清单 |

#### 第 3 步完成验收

```bash
# 1. 审计可用
node scripts/harness/cli.mjs upgrade:audit --from 5.5 --to 5.6
# → 输出 JSON 影响报告

# 2. 基线+验证可用
node scripts/harness/cli.mjs upgrade:baseline --save && upgrade:verify
# → 对比通过

# 3. 回滚可用
node scripts/harness/cli.mjs upgrade:rollback
# → 成功回到升级前状态

# 4. 证据包可生成
node scripts/harness/cli.mjs upgrade:evidence
# → 生成 ZIP 文件
```

---

### 第 4 步：让系统自己变强（持续进行）

**总耗时**：每次 5-30 分钟，融入日常工作
**前置条件**：第 2-3 步完成

#### 子步骤 4.1：反模式规则持续增长

**触发条件**：你或 AI 写了一段代码，人工 review 时发现"这种写法不对"，但 CI 没有拦截。

**操作模板**（5 分钟）：
1. 打开 `harness/policies/anti-patterns.json`
2. 新增一条规则：
```json
{
  "id": "AP-XXX",
  "name": "<简短描述>",
  "severity": "error|warning",
  "pattern": "<正则表达式>",
  "fileGlob": "<文件匹配>",
  "message": "<人类可读的说明>"
}
```
3. 在 `AGENTS.md` §5 的表格中新增对应行
4. 跑 `node scripts/harness/scan-anti-patterns.mjs` 确认新规则能正确检测

#### 子步骤 4.2：Skill 决策树持续精化

**触发条件**：AI 选了错误的技术方案（如本该用 Events 却写了 Decorator）。

**操作模板**（5 分钟）：
1. 打开对应的 Skill 文件
2. 在"何时使用"的说明中，增加一条："如果你的场景是 XXX，不要用这个。去用 YYY。"

#### 子步骤 4.3：Eval Scenario 持续新增

**触发条件**：发现 AI 会在某个特定任务上反复犯错。

**操作模板**（10 分钟）：
1. 打开 `harness/scenarios/scenarios.json`
2. 新增一个 Scenario，指定 `mustDo` 和 `mustNotDo`

#### 子步骤 4.4：Flaky 测试治理

**触发条件**：CI 中某个测试随机失败，重跑后又通过。

**操作模板**（2 分钟）：
1. 标记 flaky：在测试文件或 CI 配置中记录 `@flaky since=2026-07-27 owner=steven`
2. 设 7 天过期日：7 天后仍未修复 → CI 强制失败
3. 每周 review flaky 列表，优先修复频率最高的

#### 子步骤 4.5：知识同步规则表持续更新

**触发条件**：项目中新增了一种文件类型或代码模式，但 `AGENTS.md` §7 的规则表没有覆盖。

**操作模板**（3 分钟）：
1. 打开 `AGENTS.md` §7
2. 新增一行规则：代码 glob → 需同步的文档
3. 同时更新 `scripts/harness/doc-impact.mjs` 中的 `SYNC_RULES` 数组

---

## 四、建成后的一天

```
08:00  cd pallastrade && harness doctor → 10/10 ✅

08:30  客户："品牌管理加 logo 上传"

08:31  AI 输出理解报告：
       - 代码 4 文件 | 知识同步 6 项 | 不可做清单已列

08:35  你确认方案 → AI 开始实现

08:55  AI 提交 PR（10 文件 = 4 代码 + 6 知识文档）
       quick (3 min) ✅ → lint | typecheck | 单测 | 反模式 | doc-impact(6/6)
       full  (22 min) ✅ → 1200 全绿 | 覆盖率 +0.5% | 视觉回归无差异

09:20  merge → staging → 截图对比通过

09:35  客户确认 → production

09:40  ☕ 证据包自动归档
```

---

## 四.5、实例演示：新增"前台 AI 翻译"功能（完整 Harness 任务流）

> 以下用一个真实场景，完整走一遍 Harness 九项能力是如何在任务生命周期中层层生效的。

### 需求

> 客户提出：前台商城网站（Storefront）需要支持 AI 翻译功能。用户在浏览产品详情页时，可以点击"翻译"按钮，将产品描述、规格参数等文本翻译成用户当前语言。

### 阶段零：任务分类

```
AI 运行：harness affected --base origin/main
输出：{ affectedComponents: ["backend", "storefront"], estimatedTests: 18 }

任务分类结果：
  涉及新 API 端点 → 新功能路径
  涉及 Storefront UI 变更 → 同时触发样式路径的检查
  → 综合路径：新功能路径 + 样式子路径
```

### 阶段①：理解（~20 分钟）

**AI 执行序列**：

```
Step 1.1  读 AGENTS.md（根）→ 建立项目全景
          识别到：backend/app/ = 可自由修改，Storefront 用 @pallastrade/sdk
          
Step 1.2  根据决策树 §3 判断：
          "AI 翻译是一个新服务" → 优先考虑 DI（PallasTrade.dependencies）
          "需要新增 API 端点" → 需要 Generator 或手写 Controller
          "Storefront 新增交互组件" → 需要新组件 + SDK 调用
          
Step 1.3  读相关 Skill：
          - pallastrade-customization → 确认决策树路径
          - pallastrade-dependencies → 了解 DI 替换模式
          - pallastrade-api-v3 → 了解 API 约定
          - pallastrade-storefront → 了解 Storefront 组件规范
          - pallastrade-i18n → 了解多语言支持机制
```

**AI 输出理解报告**：

```markdown
## 任务理解报告：Storefront AI 翻译功能

### 基本信息
- 任务类型：新功能
- 影响组件：backend, storefront
- 需查阅的 Skill：pallastrade-dependencies, pallastrade-api-v3, pallastrade-storefront, pallastrade-i18n

### 决策树结果
- 核心服务层：PallasTrade.dependencies（DI）→ 注入 AITranslationService
  理由：翻译是"如何计算/获取数据"的问题，属于 DI 的标准场景
- API 层：手写 Controller（继承 PallasTrade::Api::V3::BaseController）
  理由：翻译端点不是标准 CRUD，pallastrade:api_resource 不适用
- Storefront 层：新增 TranslationButton 组件 + SDK 调用
  理由：遵循 pallastrade-storefront 的组件规范

### 影响范围
- 需新增的文件（预估）：12 个
- 需修改的文件（预估）：3 个
- 影响的已有功能：产品详情页（新增 UI 元素，不影响现有逻辑）

### 风险点
- 最高风险：AI 翻译 API 密钥管理（不能硬编码）
- 回滚难度：低（DI 替换 + Feature Flag 控制开关）

### 最小验证集
- [x] harness check --profile quick
- [x] harness generated:check（新增 API 端点 → OpenAPI + SDK Types）
- [x] harness e2e storefront（UI 变更）
- [x] harness eval ai --check-freshness（Skill 有更新）
- [x] harness doc-impact --base origin/main（知识文档同步检查）
```

### 阶段②：方案（~30 分钟）

**AI 走决策树 + 屎山检查 + 三元组清单**：

```markdown
## 实现方案：Storefront AI 翻译功能

### 技术路线
- 扩展层级：Dependency Injection（PallasTrade.dependencies）
- 关键决策：
  · 翻译服务本身通过 DI 注入 → 默认用 OpenAI，未来可替换为 DeepL/Google
  · API 端点挂在 /api/v3/store/products/:id/translate → 遵循 Store API 命名约定
  · Storefront 用 @pallastrade/sdk 调用，不手写 fetch

### 文件变更清单
| 文件 | 操作 | 类型 | 风险 |
|---|---|---|---|
| backend/app/services/pallastrade/ai_translation_service.rb | 新增 | 客户代码 | 低 |
| backend/config/initializers/pallastrade.rb | 修改 | 客户配置 | 中 |
| backend/app/controllers/pallastrade/api/v3/store/translations_controller.rb | 新增 | API | 中 |
| storefront/src/components/translate-button.tsx | 新增 | UI 组件 | 低 |
| storefront/src/app/products/[slug]/page.tsx | 修改 | 页面 | 低 |
| backend/app/decorators/pallastrade/product_decorator.rb | 新增 | Decorator | 低 |

### 三元组清单
- [ ] Skill 更新：
      · pallastrade-dependencies（新增 AITranslationService 替换示例）
      · pallastrade-api-v3（新增 /translate 端点说明）
      · pallastrade-storefront §Components（新增 TranslateButton 组件）
      · pallastrade-i18n（补充 AI 翻译模式）
- [ ] Eval 场景：GS-012（Storefront AI 翻译功能）
- [ ] 单元测试：ai_translation_service_spec.rb
- [ ] 请求测试：translations_controller_spec.rb
- [ ] 组件测试：translate-button.test.tsx
- [ ] E2E 测试：storefront/e2e/translate.spec.ts

### 不可做清单
- [ ] 不硬编码 OpenAI API Key（走 Rails credentials 或 ENV）
- [ ] 不手写 fetch('/api/v3/store/...')（走 @pallastrade/sdk）
- [ ] 不用 inline style（走 Tailwind className）
- [ ] 不跳过 loading/error 状态（组件必须处理三种状态）
- [ ] 不在产品详情页直接调翻译 API（封装到 TranslateButton 组件内）
- [ ] 不绕过 current_store scope（翻译请求需验证产品属于当前 store）

### 回滚方案
- Feature Flag：PALLAS_TRANSLATION_ENABLED=false 即可关闭
- DI 回滚：移除 initializer 中的注册即可
```

### 阶段③：实现（~2 小时）

**AI 严格按照"Test 先行 → Code + Skill + Eval 同步"的顺序**：

```
Step 3.1  写测试（先于实现）：
          ├── spec/services/pallastrade/ai_translation_service_spec.rb
          │   - 正常翻译返回译文
          │   - API 超时时返回原文 + 降级标记
          │   - 空文本不调用 API
          ├── spec/requests/pallastrade/api/v3/store/translations_spec.rb
          │   - 使用 prefixed ID（prod_xxx）
          │   - Store scope 隔离
          │   - 未登录用户返回 401
          └── storefront/src/components/__tests__/translate-button.test.tsx
              - loading 状态显示 spinner
              - 翻译成功显示译文
              - API 失败显示错误提示

Step 3.2  写实现代码：
          ├── backend/app/services/pallastrade/ai_translation_service.rb
          │   （DI 注入的服务类，调用 OpenAI API）
          ├── backend/config/initializers/pallastrade.rb
          │   （注册 PallasTrade.dependencies.ai_translation_service）
          ├── backend/app/controllers/.../translations_controller.rb
          │   （继承 BaseController，JSON 响应，prefixed ID）
          └── storefront/src/components/translate-button.tsx
              （Tailwind 样式，SDK 调用，三种状态处理）

Step 3.3  同步更新 Skill（实时约束检查）：
          ├── ai/skills/pallastrade-dependencies/SKILL.md
          │   新增：## Example: AI Translation Service
          ├── ai/skills/pallastrade-api-v3/SKILL.md
          │   新增：POST /api/v3/store/products/:id/translate
          ├── ai/skills/pallastrade-storefront/SKILL.md
          │   新增 §Components：TranslateButton
          └── ai/skills/pallastrade-i18n/SKILL.md
              新增：## AI-Powered Translation Mode

Step 3.4  新增 Eval Scenario：
          harness/scenarios/scenarios.json
          {
            "id": "GS-012",
            "name": "Add AI translation to Storefront",
            "mustDo": [
              "Use PallasTrade.dependencies for the translation service",
              "Use @pallastrade/sdk for API calls in Storefront",
              "Use prefixed IDs in API responses",
              "Handle loading/error/success states in UI"
            ],
            "mustNotDo": [
              "Hardcode API keys in source",
              "Raw fetch() to translation endpoint",
              "Inline styles in TranslateButton",
              "Skip error state handling"
            ]
          }

Step 3.5  本地跑 quick profile：
          harness check --profile quick → 3 min ✅
          - lint ✅ | typecheck ✅ | 受影响单测(12 个) ✅
          - 反模式扫描 ✅（无 AP-001~AP-007 违规）
          - 安全钩子 ✅（无危险命令）
```

### 阶段④：验证（~25 分钟 CI + 人工确认）

```
Step 4.1  AI push PR → CI 自动触发

          harness check --profile quick → 3 min ✅（见上）

Step 4.2  harness check --profile full → 22 min
          ├── Backend RSpec（全部 Gem spec + 新增 3 个 spec）→ 1242/1242 ✅
          ├── Platform Vitest（全部 + 新增 1 个组件测试）→ 258/258 ✅
          ├── Dashboard E2E（34 个）→ 34/34 ✅（翻译功能不影响 Admin）
          ├── Storefront E2E（1 个原有 + 1 个新增 translate.spec.ts）→ 2/2 ✅
          ├── 覆盖率：Ruby 82.3% → 82.7%（+0.4%），TS 76.1% → 76.5%（+0.4%）
          ├── 视觉回归：TranslateButton 组件截图已生成基线
          ├── 生成物漂移：✅（store.yaml 已更新，SDK types 已重新生成）
          └── 安全扫描：Brakeman ✅ | bundle-audit ✅

Step 4.3  harness doc-impact --base origin/main → 自动检查
          ┌──────────────────────────────────────────────────────┐
          │ 本次 PR 变更：                                          │
          │   + backend/app/services/.../ai_translation_service.rb │
          │   + backend/app/controllers/.../translations_controller.rb │
          │   + storefront/src/components/translate-button.tsx     │
          │   + backend/config/initializers/pallastrade.rb         │
          │                                                        │
          │ 📋 根据 AGENTS.md §7 知识同步规则，需要更新：             │
          │   [✓] pallastrade-dependencies SKILL.md     ← 已更新   │
          │   [✓] pallastrade-api-v3 SKILL.md          ← 已更新   │
          │   [✓] pallastrade-storefront SKILL.md      ← 已更新   │
          │   [✓] pallastrade-i18n SKILL.md            ← 已更新   │
          │   [✓] store.yaml (OpenAPI)                 ← 已更新   │
          │   [✓] storefront/e2e/translate.spec.ts     ← 已新增   │
          │   [✓] harness/scenarios/scenarios.json     ← 已新增   │
          │                                                        │
          │ ✅ 7/7 知识文档已同步。PR 可以合并。                      │
          └──────────────────────────────────────────────────────┘

Step 4.4  你 review PR：
          - 核心逻辑：AI 翻译服务通过 DI 注入 ✅（不是 monkey-patch）
          - API 约定：prefixed ID、Store scope、JSON envelope ✅
          - 组件：三种状态处理完整，Tailwind 样式，无 inline style ✅
          - Skill 更新：4 个 Skill 文件都有实质性更新 ✅
          - 测试覆盖：单元 + 请求 + 组件 + E2E 全覆盖 ✅
          → 批准合并
```

### 阶段⑤：交付（~15 分钟）

```
Step 5.1  merge main → staging 自动部署

Step 5.2  截图对比：
          产品详情页 before/after → TranslateButton 出现在预期位置，无布局偏移

Step 5.3  渐进交付：
          第 1 层：Feature Flag PALLAS_TRANSLATION_ENABLED=true（仅内部 Admin 可见）
          第 2 层：内部 Admin 先体验 → 确认翻译质量 OK
          第 3 层：5% Storefront 流量 → Nightly CI 监控性能无劣化
          第 4 层：全量发布

Step 5.4  客户通知："AI 翻译功能已上线，这是自动生成的交付证据"
          ├── 代码变更：12 个新增 + 3 个修改
          ├── 知识同步：7 个文档已更新
          ├── 测试证据：1242+258 全绿，覆盖率 +0.4%
          └── 回滚方案：PALLAS_TRANSLATION_ENABLED=false 即刻关闭
```

### 🔄 反哺（任务完成后 5 分钟）

```
本次任务中发现：
1. AI 最初尝试在 Product 模型上直接加 translate 方法（跳过了 DI 决策树）
   → 反哺：pallastrade-customization Skill 补充一条："翻译类服务 ≠ Model 方法，
     应该走 DI。参考 pallastrade-dependencies Skill §AI Translation Example"

2. Storefront 组件测试中，AI 首次写的 loading 状态只用了文字"Loading..."
   → 反哺：pallastrade-storefront Skill §Components 补充：
     "Loading 状态必须使用 <Skeleton /> 或 <Spinner /> 组件，禁止纯文字"

3. doc-impact 检查发现 pallastrade-i18n Skill 原本没有"AI 翻译模式"章节
   → 本次已补充，后续类似功能可参考
```

### 九项核心能力在本任务中的体现

| # | 能力 | 在本任务中如何生效 |
|---|---|---|
| ① | AI 只读真信息 | AI 读了 AGENTS.md + 4 个 Skill（路径已在第 1 步修正） |
| ② | AI 写不出屎山 | 反模式扫描检查了 inline style、raw fetch、Model.create（均无违规） |
| ③ | AI 做不了危险操作 | 安全钩子全程监控，AI 未尝试危险命令 |
| ④ | 5 分钟知结果 | quick profile 3 分钟给出 lint/typecheck/单测/反模式结果 |
| ⑤ | 测试不是摆设 | 全量 1242+258 测试在 full profile 中执行，新增 4 个 spec |
| ⑥ | 升级像拨开关 | Feature Flag 控制 + DI 注入 → 出问题关 Flag 即可 |
| ⑦ | 交付 = 证据 | 自动生成交付证据：代码+测试+覆盖率 |
| ⑧ | 系统越用越强 | 2 条反哺写入 Skill，未来 AI 不会再犯同类错误 |
| ⑨ | 代码知识同步 | doc-impact 自动检查：7/7 知识文档已同步（CI 强制执行） |

### 这个实例说明的核心价值

> **不是"AI 帮你写了一个翻译功能"——而是"Harness 确保了从需求到交付的每一步都是可靠的"。** AI 写的代码经过了决策树审核、反模式拦截、全量测试、覆盖率门禁、知识同步检查。你不需要盯着 AI 的每一步——你只需要在方案阶段确认方向，在 PR 阶段 review 结果。中间的一切，Harness 替你守住了。

---

## 五、投资回报

| | 投入 | 回报 |
|---|---|---|
| **时间** | 14-22 工作日（第 1-3 步） | 此后每天节省 2-3 小时 |
| **金钱** | AI API ~$50-100/月 | 不需要雇 QA/DevOps/交付经理 |
| **心力** | 前期集中，后期低维护（月均 3-4h） | **晚上睡得着觉** |
| **客户信任** | 自动证据包 | 客户信任机器数据 > 信任人的承诺 |
| **知识资产** | `doc-impact` 强制执行 | 代码和文档永不背离 |

---

## 六、立刻开始

花 30 分钟创建根 `AGENTS.md`（子步骤 1.5 的完整模板）。这是整个 Harness 体系的宪法——也是投资回报率最高的一步。

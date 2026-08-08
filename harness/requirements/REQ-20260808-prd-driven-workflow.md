# PRD 驱动的自动化开发工作流 — 方案设计

> 需求来源：用户希望通过一句话需求，驱动「PRD 生成 → 自动实施 → 测试/验收 → 文档同步」的完整闭环。
> 本文件为**方案设计文档**（本次仅输出方案，不实施）。

---

## 一、目标与原则

### 1.1 目标
1. 用户在 VS Code 聊天中输入**一句话需求**，AI 自动扩充为**详细 PRD 文档**（统一存放、统一命名、按领域自动分类）
2. AI 在 **harness 机制 + 项目规范**约束下自动实施 PRD
3. **新功能** → 自动创建自动化测试文件 + 验收机制
4. **已有功能优化迭代** → 同步升级测试、验收机制，更新/创建 PRD
5. **接口增删改查** → 同步更新 API 接口文档
6. 全程**可追溯**：需求 → PRD → 任务 → 测试 → 验收 → 文档，闭环留痕

### 1.2 设计原则
| 原则 | 说明 |
|---|---|
| **复用现有机制** | 不另起炉灶：PRD 流程**嵌入**现有 harness gate / doc-impact / generated-check / skill 体系 |
| **PRD 与 REQ 分层** | PRD = 产品需求（客户可读，含验收标准）；REQ = 开发门禁文档（harness 流程）；PRD 是 REQ 的输入，REQ 是 PRD 的执行凭证 |
| **AI 可执行** | 所有规则写入 Skill 文件（`ai/skills/`），任何 AI 助手读到即遵循 |
| **幂等** | 重复提交同一需求不重复创建 PRD（先查重） |
| **分类与 skill 对齐** | PRD 分类 = `ai/skills/` 领域，AI 写 PRD 时自动关联对应 skill |

---

## 二、PRD 存放结构

### 2.1 目录结构（新建 `docs/prd/`）

```
docs/prd/
├── README.md                  # PRD 索引（自动维护：全部 PRD 清单 + 状态 + 分类统计）
├── _TEMPLATE.md               # PRD 文档模板
├── catalog/                   # 商品/类目/搜索
│   └── PRD-20260808-catalog-bulk-import.md
├── checkout/                  # 购物车/结算/订单
├── payments/                  # 支付/退款
├── promotions/                # 促销/优惠券
├── pricing/                   # 价格/多币种
├── shipping/                  # 物流/库存/履约
├── admin/                     # 管理后台
├── storefront/                # 商城前端
├── api/                       # 接口/API 规范
├── platform/                  # SDK/CLI/平台能力
├── security/                  # 安全
├── i18n/                      # 多语言
├── harness/                   # 工程机制（本方案自身归此类）
├── infra/                     # 部署/基础设施
└── other/                     # 其他（无法自动判定时）
```

### 2.2 命名规则

```
PRD-{YYYYMMDD}-{category}-{slug}.md
例：PRD-20260808-catalog-bulk-import.md
```

- `{YYYYMMDD}`：创建日期（8 位）
- `{category}`：领域分类（小写，与 2.1 目录一一对应）
- `{slug}`：需求短名（kebab-case，≤6 个词）
- 同一分类下自动进入对应子文件夹

### 2.3 分类自动判定

**规则源**：`harness/policies/prd-categories.json`（新文件）

```json
{
  "catalog": ["商品", "产品", "类目", "分类", "taxon", "product", "variant", "搜索", "图片"],
  "checkout": ["购物车", "结算", "订单", "checkout", "cart", "order", "下单"],
  "payments": ["支付", "退款", "stripe", "payment", "refund", "发票"],
  "promotions": ["促销", "优惠券", "折扣", "promotion", "coupon", "折扣码"],
  "pricing": ["价格", "货币", "定价", "price", "currency", "多币种"],
  "shipping": ["物流", "库存", "发货", "运费", "shipping", "stock", "fulfillment", "退货"],
  "admin": ["管理后台", "后台", "admin", "侧边栏", "导航"],
  "storefront": ["商城", "前端", "页面", "storefront", "首页", "详情页", "SEO"],
  "api": ["接口", "API", "端点", "endpoint", "serializer", "schema"],
  "platform": ["SDK", "CLI", "平台", "sdk", "cli", "dashboard", "类型"],
  "security": ["安全", "权限", "认证", "加密", "security", "auth", "CVE"],
  "i18n": ["多语言", "翻译", "i18n", "国际化", "locale"],
  "harness": ["harness", "门禁", "工程", "工作流", "PRD", "gate", "CI"],
  "infra": ["部署", "Docker", "K8s", "CI", "发布", "deploy", "infra", "流水线"]
}
```

**判定流程**（AI 执行）：
1. 需求描述匹配关键词 → 取命中数最多的分类
2. 无命中 → `other/`
3. AI 可基于语义微调（记录到 PRD 元数据）

---

## 三、PRD 文档模板

每个 PRD 文档结构（`docs/prd/_TEMPLATE.md`）：

```markdown
# PRD-{YYYYMMDD}-{category}-{slug}

| 元数据 | 值 |
|---|---|
| 状态 | draft / reviewing / approved / implementing / verifying / done / rejected |
| 创建日期 | YYYY-MM-DD |
| 来源 | 一句话需求原文 |
| 分类 | catalog（自动判定） |
| 关联 Skill | pallastrade-catalog |
| 关联 REQ | REQ-20260808-xxx.md（实施时回填） |

## 1. 背景与目标
- 一句话需求原文
- 背景：为什么做、解决什么问题
- 目标：期望达成的结果
- 成功指标（可量化，如：导入 1 万 SKU 耗时 < 60s）

## 2. 用户故事 / 场景
- 作为 <角色>，我希望 <能力>，以便 <价值>
- 场景列表（正常流 + 边界 + 异常）

## 3. 功能需求（FR）
- FR-001：<可验收的功能描述>
- FR-002：...

## 4. 非功能需求（NFR）
- 性能 / 安全 / 兼容 / 可维护性

## 5. 验收标准（AC，与测试一一映射）
- AC-001 ← 对应 FR-001：<可验证的判定条件>
- AC-002 ← ...

## 6. 跨层搜索记录（6 层，gate 强制）
| 层 | 路径 | 关键词 | 找到 | 是否满足 |
|---|---|---|---|---|
| backend/app | ... | | | |

## 7. 技术影响
- 涉及组件 / 文件 / 依赖 / 数据库 / 接口
- 影响面（harness affected 输出）

## 8. 测试计划
- 新增测试文件（路径清单）
- 更新测试文件（路径 + 变更点）
- 覆盖的 AC 映射

## 9. 文档同步清单
- [ ] API 文档（若涉及接口）：backend/public/api-docs/*.yaml + platform/docs/api-reference/*.yaml
- [ ] Skill 文档（doc-impact 规则）
- [ ] 本 PRD 状态更新

## 10. 变更记录
| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
```

---

## 四、工作流（一句话需求 → 完成开发）

### 阶段 0：需求录入（AI 自动）

```
用户一句话 → AI 判定前缀/类型（复用 harness 前缀映射）
    ↓
① 查重：搜索 docs/prd/** 已有 PRD + 6 层跨层搜索，确认非重复
② 分类判定：关键词匹配 prd-categories.json → 选定 category
③ AI 自动扩充 → 生成 PRD 初稿（draft）
    docs/prd/{category}/PRD-{YYYYMMDD}-{category}-{slug}.md
④ 更新 docs/prd/README.md 索引
```

**一句话 → PRD 扩充规则**（AI 必须完成）：
- 需求类型判定：新功能 / 优化迭代 / Bug 修复 / 接口变更 / 样式 / 文档
- 自动拆解出 FR + AC（每个 FR 至少 1 个 AC）
- 自动识别测试影响（新增 or 更新）
- 自动识别接口影响（是否涉及 controller/routes → 标记需同步 API 文档）

### 阶段 1：PRD 评审（用户确认）

```
AI 呈现 PRD 初稿 → 用户确认（approve）或修改
    ↓
① 用户确认后 PRD 状态 → approved
② 进入 harness gate 流程（新建 gate）
```

### 阶段 2：门禁 + 实施（harness 约束下）

```
harness gate --task "<PRD 标题>"（feature/bugfix/...）
    ↓
依据 PRD 生成 REQ 文档（harness/requirements/REQ-{date}-{slug}.md，回填 PRD 关联）
    ↓
清除 gate checks（搜索 / skill / req-doc / user-confirmed）
    ↓
实施（按 PRD 的 FR 逐个实现）：
   ├─ 新功能 → 创建测试文件（见 §五）
   ├─ 优化迭代 → 升级测试 + 更新 PRD §8/§10
   └─ 接口变更 → 同步 API 文档（见 §六）
```

### 阶段 3：验证（R6 强制）

```
按改动类型跑最小验证（复用 AGENTS.md §6 表格）
    ↓
清除 verify-test（附证据）
    ↓
PRD 状态 → verifying → done（附测试结果）
```

### 阶段 4：收尾（知识同步门）

```
① PRD 收尾：状态 done + 变更记录 + 测试/文档同步勾选
② 知识同步门（见 §八 同步矩阵）：按本次变更类型逐项判定需更新的知识资产——
   ├─ Skill / README / Agent 文件 / 样式规范 / 视觉规范 / 技术规范
   ├─ 反模式库 / 任务规则 / 场景库 / API 文档 / 记忆
   └─ 有变更 → 更新；已评估无变更 → 在 PRD §10 记录"已评估，无需更新"
③ 更新 docs/prd/README.md 索引
④ 运行 harness doc-impact（skill 同步自动检查）+ harness eval-ai --check-freshness
```

---

## 五、测试与验收机制

### 5.1 分层测试约定（复用现有）
| 层 | 测试框架 | 位置 | 验收对应 |
|---|---|---|---|
| 后端 | RSpec + Factory Bot + Capybara | `backend/spec/{models,requests,services,features}/...` | AC 的后端逻辑 |
| Storefront | Vitest + Testing Library | `storefront/src/**/__tests__/*.test.tsx` | AC 的 UI 行为 |
| Platform | Vitest | `platform/packages/*/tests/*.test.ts` | AC 的 SDK/CLI |

### 5.2 新功能 → 自动创建
- AI 依据 PRD §5 AC 清单，为每个 AC 生成对应测试
- 测试文件命名与 PRD 关联：`xxx_spec.rb` / `xxx.test.ts`（测试头部注释 `# PRD-20260808-xxx AC-001`）
- **验收机制**：每个 PRD 的 AC 必须**有测试覆盖**，无测试的 AC 不允许标记 done

### 5.3 优化迭代 → 同步升级
- AI 定位已有测试文件（跨层搜索测试目录）
- 新增/修改测试以覆盖变更后的 AC
- 更新 PRD §8 测试计划 + §10 变更记录

### 5.4 AC → 测试 → 代码 三层追溯
```
PRD AC-001 ──→ 测试用例（backend/spec/.../xxx_spec.rb）──→ 实现代码
      ↑                ↑                                        ↑
  （PRD 文档）     （测试头部标注 AC 编号）            （harness 可追踪）
```

### 5.5 验收强制（新增 harness 能力，后续实施）
- `harness prd verify --id PRD-xxx`：检查每个 AC 是否有对应测试（按标注解析）
- 在 `verify-test` gate check 前自动执行，AC 未覆盖 → 阻止 done

---

## 六、API 接口文档同步

### 6.1 接口变更检测（AI 实施时识别）
- 修改了 `backend/app/controllers/**/api/v3/**/*.rb` 或 gem 内 controller/routes
- 或 PRD 分类判定为 `api`

### 6.2 同步更新位置（复用现有）
| 文档 | 位置 | 何时更新 |
|---|---|---|
| Store API OpenAPI | `backend/public/api-docs/store.yaml` | Store 接口变更 |
| Admin API OpenAPI | `backend/public/api-docs/admin.yaml` | Admin 接口变更 |
| SDK 引用文档 | `platform/docs/api-reference/{store,admin}.yaml` | 上述变更后同步 |

### 6.3 验证
- `harness generated:check`（SDK types + CLI spec 再生成，检测 drift）
- `pnpm --filter @pallastrade/sdk generate:types`
- PRD §9 文档同步清单勾选

---

## 七、harness 机制集成（落地清单）

| # | 落地项 | 文件 | 说明 |
|---|---|---|---|
| 1 | PRD 目录 + 模板 | `docs/prd/`、`docs/prd/_TEMPLATE.md`、`docs/prd/README.md` | 新功能 |
| 2 | 分类规则 | `harness/policies/prd-categories.json` | 新功能 |
| 3 | PRD Skill | `ai/skills/pallastrade-prd/SKILL.md` | **核心**：教 AI 写 PRD + 走工作流 |
| 4 | PRD 命令入口 | `ai/commands/prd.md`（Claude `/prd`） | 可选用 |
| 5 | CLI 扩展 | `scripts/harness/cli.mjs` 新增 `prd` 子命令：`prd new / prd list / prd verify` | 可选用（增强） |
| 6 | Gate 集成 | gate 的 feature checks 增加 `prd-created` | PRD 未创建则不允许实施 |
| 7 | doc-impact 扩展 | `scripts/harness/doc-impact.mjs` 增加 PRD 同步规则 | 代码变更 → PRD 需同步 |
| 8 | AGENTS.md | 增加 PRD 工作流章节 | 文档同步 |

### 7.1 PRD Skill 内容要点（`ai/skills/pallastrade-prd/SKILL.md`）
- 触发：用户输入一句话需求
- 流程：查重 → 分类 → 写 PRD → 用户确认 → gate → 实施 → 测试 → 验证 → 收尾
- 规则：
  - 必须使用 `docs/prd/_TEMPLATE.md`
  - 命名 `PRD-{date}-{category}-{slug}.md`
  - 分类用 `harness/policies/prd-categories.json`
  - 每个 FR 必须有 AC；每个 AC 必须有测试
  - 接口变更必须更新 API 文档（§六）
  - 优化迭代必须更新已有 PRD / 测试
  - 完成后更新 `docs/prd/README.md` 索引

### 7.2 与现有 REQ/gate 的关系
```
一句话需求
   ↓ AI
PRD（docs/prd/，产品需求 + AC）       ← 新增层
   ↓ AI
REQ（harness/requirements/，门禁文档） ← 现有层（复用 _TEMPLATE.md）
   ↓
harness gate → 实施 → 测试 → verify-test
   ↓
done（PRD 状态 + 索引更新 + doc-impact）
```

---

## 八、知识资产同步矩阵（核心补充）

> 用户补充要求：开发变更后，除 API 文档外，还要评估 **Skill / README / Agent 文件 / 样式规范 / 视觉规范 / 技术规范** 是否需要同步。
> 本节枚举全仓库知识资产，并给出「变更类型 → 需同步资产」判定矩阵。

### 8.1 知识资产全景盘点（本次调研枚举）

| 编号 | 资产类型 | 位置 | 作用 | 变更触发示例 |
|---|---|---|---|---|
| A1–A9 | **Agent / 指令文件** | 根 `AGENTS.md`、`.github/copilot-instructions.md`、`ai/AGENTS.md`、`backend/{AGENTS,CLAUDE}.md`、`platform/{AGENTS,CLAUDE}.md`、`storefront/{AGENTS,CLAUDE}.md` | 定义 AI 行为规范、验证要求、反模式、危险操作 | 新规范 / 新反模式 / 流程变化 |
| B1–B24 | **领域 Skill** | `ai/skills/*/SKILL.md`（24 个，含 Style Guide / Styling / 技术章节） | AI 领域知识 | 新增模型 / API / 组件 / 命令 |
| C1 | **专家 Agent** | `ai/agents/pallastrade-expert.md` | 专家代理定义 | 新领域知识 / 工具变化 |
| C2 | **AI 命令** | `ai/commands/*.md`（如 `doctor.md`） | Claude Code 斜杠命令 | 新命令 / 流程 |
| D1 | **反模式库** | `harness/policies/anti-patterns.json` | CI 强制反模式（AP-xxx） | 发现新反模式 |
| D2 | **任务规则** | `harness/policies/task-rules.json` | AI 执行规则（TR-xxx） | 新流程规则 |
| D3 | **Harness 配置** | `harness/config.json` | 覆盖率阈值 / profiles | 阈值 / 检查集调整 |
| D4 | **场景库** | `harness/scenarios/scenarios.json` | Eval 场景（GS-xxx） | 新能力需评估 |
| E1 | **API 文档** | `backend/public/api-docs/{store,admin}.yaml` + `platform/docs/api-reference/` | OpenAPI 规范（SDK 生成源） | 接口增删改查 |
| E2 | **产品文档** | `platform/docs/`（.mintlify 结构） | 客户可见文档 | 功能 / 集成变化 |
| F1 | **README** | 根、`ai/`、`backend/`、`platform/`、`storefront/`、`scripts/release/`、各包 | 使用 / 结构 / 命令说明 | 结构 / 命令 / 包变化 |
| F2 | **记忆 / 决策** | `ai/memories/*.md` | 跨会话决策记录 | 重要技术决策 |
| G1 | **技术规范** | `biome.json`、CLAUDE.md §Code Style、Ruby/Rails 约定（skill 中） | 代码风格 / 格式化 / 技术选型 | 新框架 / 依赖 / 风格约定 |
| G2 | **样式 / 视觉规范** | `storefront/CLAUDE.md` §Code Style、`ai/skills/pallastrade-storefront/SKILL.md` Style Guide 章节、`pallastrade-admin/SKILL.md` Styling 章节、Tailwind 配置 / 设计 token | UI 一致性（AP-001/AP-006） | 新增组件 / token / 视觉语言 |
| G3 | **测试约定** | `backend/spec/`、`storefront/src/**/__tests__/`、`platform/packages/*/tests/` | 验收覆盖（RSpec / Vitest） | 新功能 / 优化迭代 |

### 8.2 同步判定矩阵（变更类型 → 必须同步的资产）

| 变更类型 | 触发示例 | 必须同步的资产 |
|---|---|---|
| Model / DB 变更 | 新增/改模型、迁移 | 对应领域 Skill、`pallastrade-data-model` Skill、D4 场景、G3 测试 |
| API 端点变更 | 增删改 controller / routes / serializer | **E1**（store/admin.yaml）、`pallastrade-api-v3` Skill、SDK 类型（`generated:check`）、D4 场景 |
| UI 组件 / 页面 | 新增/改 TSX | `pallastrade-storefront` Skill §Components、G3 组件测试、D4 场景 |
| 样式 / 设计 token | 改 CSS / Tailwind / 色板 | **G2** 样式规范、`pallastrade-storefront` Skill、AP-006 检查、E2E 截图证据 |
| 事件 / 订阅者 | 新增事件/订阅者 | `pallastrade-events-webhooks` Skill |
| 新反模式 | 发现新违规模式 | **D1** anti-patterns.json + **A1** AGENTS.md §5 + A2 copilot-instructions |
| 新任务规则 | 流程规则变化 | **D2** task-rules.json + A1 AGENTS.md + PRD Skill |
| CLI / 命令能力 | 新增/改 CLI 子命令 | `pallastrade-cli` Skill、**C2** ai/commands/、CLI README |
| 包 / SDK 能力 | 新增包/改 SDK | `pallastrade-typescript-sdk` Skill、`platform/packages/README.md`、根 README |
| 技术选型 / 架构 | 新框架/依赖/目录结构 | **A1** 根 AGENTS.md、对应层 CLAUDE.md/AGENTS.md、**G1** 技术规范、F1 README |
| 安全策略 | 新安全规则/密钥轮换 | `pallastrade-security` Skill、A1 AGENTS.md §8 危险操作、密钥轮换流程 |
| 部署 / 配置 | 环境变量/部署流程 | `pallastrade-deployment` Skill、`.env.example`、部署 README |
| 流程机制 | gate / PRD / harness 变化 | 本 PRD 工作流、A1 AGENTS.md、A2 copilot-instructions、PRD Skill、D4 场景 |

### 8.3 同步机制落地

1. **doc-impact 扩展**：现有 `doc-impact.mjs` 只覆盖 Skill 同步（AGENTS.md §7 表）。扩展为**全矩阵**：新增 README / Agent / 规范 / 场景 / 反模式规则条目
2. **`harness sync-check`（新命令）**：对比本次变更文件 vs §8.2 矩阵，输出「需评估的资产清单」；AI 逐项处理，结论写入 PRD §9/§10
3. **门禁集成**：`sync-check` 结果作为 `verify-test` 前置——存在「应更新而未更新」的资产 → 阻止 done
4. **阶段 4 强制**：知识同步门（§四），每项结论（更新 / 无需更新+理由）必须留痕

---

## 九、我补充的完善点（用户未列但必要）

1. **PRD 生命周期状态机**：draft → reviewing → approved → implementing → verifying → done（+ rejected），状态记录在 PRD 元数据，索引按状态筛选
2. **防重复机制**：录入前强制 ①PRD 查重 ②6 层跨层搜索，防止重复开发（对应 AP-SEARCH 反模式）
3. **可追溯链**：FR/AC 编号贯穿 PRD → 测试 → 代码（§5.4）
4. **幂等性**：同一天同一 slug 重复创建 → 提示已存在并跳转
5. **索引自动维护**：`docs/prd/README.md` 在每次 PRD 状态变更后更新（AI 执行，或 `harness prd list` 生成）
6. **门禁前检查**：PRD 未 approved 不允许开 gate；PRD 未 done 不允许关闭 gate（verify-test 前跑 `prd verify`）
7. **接口变更自动标记**：PRD 生成时 AI 预判接口影响，直接写入 §9 清单
8. **异常流程**：Bug 修复类需求 → 走 bugfix gate，但同样生成 PRD（简版，可省略用户故事，聚焦复现步骤 + 验证）
9. **权限/安全影响**：涉及 security 分类时强制阅读 pallastrade-security skill + 密钥轮换检查

---

## 十、实施计划（本次不实施，后续按序推进）

| 步骤 | 内容 | 工作量 |
|---|---|---|
| P1 | 创建 `docs/prd/` 目录 + `_TEMPLATE.md` + `README.md` | 小 |
| P2 | 创建 `harness/policies/prd-categories.json` 分类规则 | 小 |
| P3 | 创建 `ai/skills/pallastrade-prd/SKILL.md`（核心工作流，含知识同步门） | 中 |
| P4 | gate 集成：feature checks 增加 `prd-created` | 中 |
| P5 | CLI 扩展：`prd new / list / verify` 子命令 | 中 |
| P6 | doc-impact 扩展：PRD 同步规则 | 小 |
| P7 | AGENTS.md / copilot-instructions.md 增加 PRD 工作流章节 | 小 |
| P8 | 端到端演练：用一个示例需求走通全流程 + 更新 scenarios.json | 中 |
| P9 | 创建 `docs/standards/` 规范资产索引（样式/视觉/技术/命名规范登记，指针到分散的 CLAUDE.md / Skill 章节） | 中 |
| P10 | 扩展 `doc-impact.mjs` 为全矩阵（Skill/README/Agent/规范/场景/反模式） | 中 |
| P11 | 新增 `harness sync-check` 命令（知识同步门） | 中 |
| P12 | scenarios.json 增加 PRD 工作流 + 知识同步 Eval 场景 | 小 |

---

## 十一、风险与对策

| 风险 | 等级 | 对策 |
|---|---|---|
| PRD 增加流程负担 | 中 | PRD 模板精简；bugfix 用简版模板；AI 自动完成大部分 |
| 知识资产同步遗漏 | 中 | §8.2 矩阵 + `sync-check` 门禁 + 阶段 4 知识同步门强制留痕 |
| AI 分类不准 | 低 | 关键词规则 + AI 语义微调 + 可手动改类目 |
| 测试漏覆盖 AC | 中 | `prd verify` 强制 AC↔测试映射检查 |
| 与现有 REQ 流程冲突 | 低 | PRD 是 REQ 的上游，二者串接不重叠 |
| 历史需求无 PRD | 中 | 优化迭代时若 PRD 不存在 → 自动创建（用户需求点 4） |

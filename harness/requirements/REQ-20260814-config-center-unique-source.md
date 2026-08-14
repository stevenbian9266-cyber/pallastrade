# REQ-20260814-config-center-unique-source — 配置中心唯一源语义强化

> 需求标题：优化：配置中心唯一源语义强化（Import from ENV 改为一次性初始化向导，移除 ENV 优先开关）
> 关联 PRD：PRD-20260814-admin-管理后台新增安全配置管理模块-oss-key-secret-值托管.md（v0.4）
> 任务类型：feature（优化）

---

## Step 0：跨层搜索（已执行）

| 层 | 搜索路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | ConfigItem、ConfigCenter、配置中心 | 无（配置中心在 gem 层） | 不涉及 |
| Core models | `pallastrade_core/app/models/` | ConfigItem、config | `app/models/pallastrade/config_item.rb`（已有，本次优化） | 部分——保留 |
| Core services | `pallastrade_core/lib/` | ConfigCenter、sync_env、env_precedence | `lib/pallastrade/config_center.rb`（sync_env! 含 env_precedence，本次移除） | 是——本次修改 |
| API | `pallastrade_api/app/controllers/` | config_items、import | `api/v3/admin/config_items_controller.rb`（import 端点，本次调整描述） | 部分——保留 import（bulk）或仅改语义 |
| Admin | `pallastrade_admin/app/` | config_items、import、Import from ENV | `config_items_controller.rb`（import 动作）、`views/.../index.html.erb`（Import 卡片）、locales | 是——本次改名 + 唯一源标注 |
| Storefront | `storefront/src/` | config、setting | 无 | 不涉及 |
| Platform | `platform/packages/` | configItems | 无（SDK 未扩展） | 不涉及 |

**搜索结论**：配置中心能力已存在（core/api/admin 三层齐全）。本次为**语义强化**：① admin 的 Import from ENV 改名「一次性初始化向导」并标注唯一源；② `ConfigCenter.sync_env!` 移除 `env_precedence` 参数（配置中心永远优先）；③ 知识文档同步。**无需新增模型/端点**，仅修改现有实现与文案。

---

## Step 1：Skill 文件咨询（已执行）

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | "Customize an admin table → `PallasTrade.admin.tables.<key>.add ...`"；"Add a menu item / nav entry → `settings_nav.add :config_center`" —— 配置中心属 Admin 层定制，直接改 gem 源文件（AP-008） |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | "Config Center lives under Settings (`settings_nav.add :config_center`, `ConfigItemsController` with `SettingsConcern`)"；"Import wizard (`POST /admin/config_items/import` with `env_keys[]`) reads ENV server-side and infers secret vs string" —— 本次将 Import wizard 改为一次性初始化向导并标注唯一源 |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | "命中相似 PRD → `harness prd update` 回写原 PRD（走优化迭代流程），不新建" —— 已用 `harness prd update` 回写 PRD v0.4 |

**按需 Skill**：pallastrade-api-v3（config_items 端点文档同步）、pallastrade-security（secret 只写不读语义不受影响）—— 本次涉及，实施后同步。

---

## 需求内容

### 背景

配置中心已上线（PRD v0.2/v0.3 实施）。用户澄清核心语义：**配置中心是唯一配置源**——在后台设置参数值并保存，应用通过 `ConfigCenter.get(key)` 取「参数名 + 值」，无需在 .env 手填值。当前实现中「Import from ENV」功能名称与"从 ENV 导入"的交互造成"ENV 才是配置源"的误解；且 `sync_env!` 的 `env_precedence`（ENV 优先）开关与唯一源理念冲突。

### 变更点

1. **Admin「Import from ENV」→「一次性初始化向导」**（FR-004/FR-008）
   - index 卡片标题/文案改为「从环境变量初始化（一次性迁移）」，明确标注「仅首次迁移用，迁移后配置中心为唯一源，请在此设置并保存参数」
   - 控制器 import 动作保留（server-side 读 ENV 值），`suggested_env_keys` 保留（预填）
   - locales 文案更新（en.yml）
   - 注释明确"一次性迁移"
2. **移除 `env_precedence`**（FR-007/AC-009）
   - `ConfigCenter.sync_env!` 移除 `env_precedence:` 参数，始终配置中心覆盖 ENV
   - 类注释/initializer 注释强化"唯一源、ENV 仅兜底"
3. **知识同步**
   - `ai/skills/pallastrade-admin/SKILL.md`：Import wizard 描述 → 一次性初始化向导 + 唯一源
   - `ai/skills/pallastrade-api-v3/SKILL.md`：import 端点语义（如保留则标注）
   - PRD 索引/变更记录已更新（v0.4）
   - scenarios.json：GS-026 相关场景补充唯一源语义（如涉及）

### 验收（AC）

- AC-009：配置中心已设置值与 ENV 不同时，`ConfigCenter.get` 返回配置中心值；`sync_env!` 不接受 `env_precedence` 参数（ArgumentError）
- AC-003（更新）：admin 初始化向导 UI 标题含「一次性/初始化」且标注「配置中心为唯一源」
- 回归：config_item/config_center/api/admin 4 个 spec 全绿

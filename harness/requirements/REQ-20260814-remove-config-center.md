# REQ-20260814-remove-config-center — 彻底移除 Config Center 模块

> 需求标题：优化：彻底移除 Config Center 模块，回归 .env + scan-secrets 防泄露
> 关联 PRD：PRD-20260814-admin-管理后台新增安全配置管理模块-oss-key-secret-值托管.md（标记废弃）
> 任务类型：feature（优化/逆向）

---

## Step 0：跨层搜索（已执行）

| 层 | 搜索路径 | 搜索关键词 | 找到的文件 | 处理 |
|---|---|---|---|---|
| Core models | `pallastrade_core/app/models/` | ConfigItem | `config_item.rb` | 删除 |
| Core lib | `pallastrade_core/lib/` | ConfigCenter、ServiceResolver、core.rb require | `config_center.rb`、`storage/service_resolver.rb`、`core.rb:558` | 删除/移除 require |
| Core factory | `pallastrade_core/lib/testing_support/` | config_item_factory | `factories/config_item_factory.rb` | 删除 |
| App | `backend/config/` | config_center、production.rb | `initializers/config_center.rb`、`environments/production.rb:22` | 删/回退 ENV |
| API | `pallastrade_api/` | config_items_controller、serializer、routes、dependencies | controller、serializer、`routes.rb:268`、`dependencies.rb` | 删/移除注册 |
| Admin | `pallastrade_admin/` | config_items_controller、views、navigation、tables、locales、routes | controller、views、`_config_item_value`、navigation config_center、tables、locales、`routes.rb` | 删/移除 |
| Store | `pallastrade_core/app/models/store.rb` | has_many :config_items | `store.rb` | 移除关联 |
| 迁移 | `pallastrade_core/db/migrate` + `backend/db/migrate` | create_pallastrade_config_items | 20260814000001（保留历史） | 新增 drop 迁移 |
| 测试 | `backend/spec/` | config_item/config_center/config_items | 4 个 spec | 删除 |
| 知识 | `ai/skills`、`docs/prd`、`harness/scenarios` | Config Center | admin/api-v3/security skill、PRD、GS-026/027 | 清理/标记废弃 |

**结论**：移除 Config Center 全部代码 + 测试 + 知识引用；新增 drop 表迁移；`production.rb` active_storage 回退直接读 ENV；**服务器回填 `.env.dev/.env.prod` 必需密钥（OSS_* 5 项 + TURNSTILE_SECRET_KEY）**；`pallastrade_config_items` 表 drop。

---

## Step 1：Skill 文件咨询（已执行）

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `pallastrade-customization` | ✅ 已读 | 决策树：普通配置用 Config 机制；本模块移除属于逆向（Admin 层改动，直接改 gem 源文件） |
| `pallastrade-admin` | ✅ 已读 | Config Center 在 developers_tabs 第 4 项 → 移除导航注册 |
| `pallastrade-prd` | ✅ 已读 | 优化迭代回写原 PRD（标记废弃） |

---

## 需求内容

### 背景

目标客户为无研发能力用户，主要用 AI coding 工作流。分析结论：`.env`/配置文件是 AI 可直接读写交互的自然配置层；Config Center（DB 存储）对 AI 不透明、UI 对非技术用户无价值 → **彻底移除 Config Center**，回归纯 `.env` + `harness scan-secrets` 防 secret 误提交。

### 变更点

1. **代码移除**：core（ConfigItem/ConfigCenter/ServiceResolver/factory/store 关联）、api（controller/serializer/routes/dependencies）、admin（controller/views/navigation/tables/locales/routes）、app（initializer/production.rb 回退）、测试（4 spec）
2. **DB**：新增 drop 迁移删除 `pallastrade_config_items` 表（保留创建迁移历史）
3. **服务器回填**：从配置中心 DB 读回 `oss.*`（5 项）+ `turnstile.secret_key` 明文 → 写回 `deploy/.env.dev` 与 `deploy/.env.prod`（`OSS_*`、`TURNSTILE_SECRET_KEY`）
4. **知识清理**：admin/api-v3/security skill 移除 Config Center 小节；PRD 标记废弃；scenarios GS-026/027 移除或更新；REQ 记录

### 验收（AC）

- AC-001：代码库无 ConfigItem/ConfigCenter/ServiceResolver 残留引用（grep 干净，除迁移历史/PRD 历史记录）
- AC-002：`pallastrade_config_items` 表 drop 迁移可执行；schema.rb 更新
- AC-003：`production.rb` active_storage 直接读 ENV 正常；移除后 dev/prod 重启 OSS 上传正常
- AC-004：`.env.dev`/`.env.prod` 回填 OSS_* + TURNSTILE_SECRET_KEY 后，OSS 存储与 Turnstile 验证正常
- AC-005：移除相关 spec 后，其余 spec 全绿

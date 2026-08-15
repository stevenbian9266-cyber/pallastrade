# PRD-20260815-other-redirect-增加标题与描述字段

| 元数据 | 值 |
|---|---|
| 状态 | approved（2026-08-15 用户确认） |
| 创建日期 | 2026-08-15 |
| 来源 | 优化：redirect 页面列表只有 From path/To path/Status code/Active 四个字段，不友好，用户不知道是对什么业务做了重定向，需要增加标题、描述字段 |
| 分类 | other（自动判定） |
| 关联 Skill | pallastrade-admin、pallastrade-api-v3、pallastrade-data-model |
| 关联 REQ | REQ-20260815-redirect-title-description.md（实施时回填） |
| 关联 PRD | 能力本体见 PRD-20260814-catalog-seo-...；文案/清单见 PRD-20260815 两份 |
| 需求类型 | 优化迭代 |

## 1. 背景与目标

- **一句话需求原文**：redirect 页面列表只有 From path、To path、Status code、Active 四个字段，很不友好，用户不知道是对什么业务做了重定向，需要增加标题、描述这种字段
- **背景**：redirects 列表仅显示路径与状态码，无法直观看出"这条重定向对应什么业务"（如"Air Fryer URL 规范化"、"旧首页改版"）。对运营/店主不友好，难以管理与检索。
- **目标**：Redirect 增加可选的 `title`（标题）与 `description`（描述）字段；Admin 列表新增 Title 列；表单可填写；Admin API 支持读写。旧数据无需回填（可空）。
- **成功指标**：列表首列显示业务标题；新建/编辑可填写标题与描述；API 返回/写入 title/description。

## 2. 用户故事 / 场景

- 作为店主/运营，我希望在重定向列表看到每条规则的业务标题（如"Espresso 改名重定向"），以便快速识别和管理。
- 作为运营，我希望创建/编辑重定向时填写标题与备注，说明这条重定向的业务背景。
- 场景：列表管理（Title 列）、新建（表单填 title/description）、编辑（补充描述）。

## 3. 功能需求（FR）

- FR-001：`PallasTrade::Redirect` 新增可选 `title`（string）与 `description`（text）列（迁移），旧数据可空
- FR-002：Admin 表单（`_form.html.erb`）新增 Title、Description 输入（均可选；Title 有 placeholder/help）
- FR-003：Admin 列表新增 **Title 列**（默认显示、可排序、可筛选，position 5 置于最前），from_path 等列后移
- FR-004：Admin API serializer 返回 `title`/`description`；`permitted_attributes` 支持写入；Controller `permitted_resource_params` 自动包含

## 4. 非功能需求（NFR）

- 不破坏现有 resolve 端点与 storefront 中间件（store 端 resolve 无需返回 title/description）
- 兼容旧数据（两列可空，不设默认值）
- 列表布局不因 Title 列过宽破坏（Title 用 string 列）

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：迁移后 `pallastrade_redirects` 含 `title`/`description` 列，旧记录可空
- AC-002 ← FR-002：GET `/admin/redirects/new` 渲染 Title/Description 输入框；带 title/description 创建成功
- AC-003 ← FR-003：GET `/admin/redirects` 列表含 Title 列且显示已填标题
- AC-004 ← FR-004：Admin API `POST /api/v3/admin/redirects` 带 title/description 创建并返回；列表响应含两字段

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | redirect | 无（仅 AI controller redirect_to） | 否 |
| Core | `pallastrade_gems/pallastrade_core/app/` | redirect/title | `redirect.rb`（无 title/desc）；`permitted_attributes.rb:212`（`@@redirect_attributes`） | 需改：加列 + permitted |
| API | `pallastrade_gems/pallastrade_api/app/` | redirect | `admin/redirect_serializer.rb`（4 字段）；`store/redirects_controller.rb`（resolve 仅 path/status） | 需改：admin serializer 加字段；store resolve 不动 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | redirect/tables | `_form.html.erb`；`tables.rb:2165`（4 列注册） | 需改：表单 + Title 列 |
| Storefront | `storefront/src/` | redirect | `lib/pallastrade/middleware.ts`（仅消费 resolve） | 否，无需改 |
| Platform | `platform/packages/` | redirect | 仅文档 | 否 |

**结论**：改动集中在 Core（迁移+permitted）、API（serializer）、Admin（表单+列表）；无跨层重复风险。Storefront/Platform 不受影响。

## 7. 技术影响

- 涉及文件：
  - `backend/db/migrate/` + `pallastrade_core` 迁移：`add_column :title, :string` + `add_column :description, :text`（pallastrade_redirects）
  - `pallastrade_core/lib/pallastrade/permitted_attributes.rb`：`@@redirect_attributes` + `:title, :description`
  - `pallastrade_api/.../admin/redirect_serializer.rb`：+ `title`/`description`
  - `pallastrade_admin/.../redirects/_form.html.erb`：+ Title/Description 输入
  - `pallastrade_admin/config/initializers/pallastrade_admin_tables.rb`：+ Title 列（position 5）
  - `pallastrade_admin/config/locales/en.yml`：+ title/description 相关文案
  - `spec/.../admin/redirects_spec.rb` + `api/v3/admin/redirects_spec.rb` + factory
- 数据库：新增 2 列（迁移）；无数据回填
- 接口：Admin API 响应/入参增加 title/description（向后兼容，可选字段）

## 8. 测试计划

- 迁移测试：schema 含新列（由迁移本身验证）
- model/factory：`create(:redirect, title:, description:)`
- Admin UI：new 渲染 title/description 输入 + 列表 Title 列
- Admin API：POST 带 title/description 创建并返回；GET 列表含字段
- 本地 `docker compose exec web env DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec ...` 全绿

## 9. 文档同步清单

- `ai/skills/pallastrade-admin/SKILL.md`：redirects 段落补充 title/description 字段说明
- `ai/skills/pallastrade-api-v3/SKILL.md`：admin redirects API 字段补充（如该 skill 列了字段）
- `backend/public/api-docs/admin.yaml`：Redirect schema 补充 title/description（接口变更同步）
- `harness/scenarios/scenarios.json`：GS-028 description 补充 title/description（改 skill 触发 doc-impact）
- `docs/prd/README.md` 索引

## 10. 变更记录

- 2026-08-15：创建 PRD（reviewing），待用户确认

# REQ-20260815-redirect-title-description

> 关联 PRD：PRD-20260815-other-redirect-增加标题与描述字段（approved）
> 任务：TASK-20260815054846-5054ace2

## Step 0：跨层搜索（已执行，结论见 PRD §6）

| 层 | 路径 | 关键词 | 找到的文件 | 是否满足 |
|---|---|---|---|---|
| App | `backend/app/` | redirect | 无 | 否 |
| Core | `pallastrade_gems/pallastrade_core/app/` | redirect/title | `redirect.rb`（无 title/desc）；`permitted_attributes.rb:212` | 需改 |
| API | `pallastrade_gems/pallastrade_api/app/` | redirect | `admin/redirect_serializer.rb`；store resolve（不动） | 需改 serializer |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | redirect/tables | `_form.html.erb`；`tables.rb:2165`（4 列） | 需改 |
| Storefront | `storefront/src/` | redirect | middleware（仅消费 resolve） | 否 |
| Platform | `platform/packages/` | redirect | 仅文档 | 否 |

## Step 1：Skill 文件咨询

| Skill | 状态 | 关键结论引用 |
|---|---|---|
| `pallastrade-customization` | ✅ 已读 | 模型加字段 → Core 直接改模型+迁移；Admin 视图直接改 gem views（决策树第 8 路径） |
| `pallastrade-admin` | ✅ 已读 | FormBuilder `pallastrade_text_field`；列表用 `PallasTrade.admin.tables.register` 注册列（title 列 position 5 前置）；`page_alerts` 先例 |
| `pallastrade-api-v3` | ✅ 已读 | Admin API serializer 用 `attributes`+`typelize`；permitted 走 `PermittedAttributes`；接口变更需同步 api-docs yaml |
| `pallastrade-data-model` | ✅ 已读 | 模型/DB 变更：新迁移（core + backend 双份），`db/migrate` 禁止手改 schema |

## 实施内容

1. 迁移（core + backend）：`pallastrade_redirects` + `title:string` + `description:text`（可空）
2. `permitted_attributes.rb`：`@@redirect_attributes` + `:title, :description`
3. `admin/redirect_serializer.rb`：+ `title`/`description`（typelize string/text nullable）
4. `_form.html.erb`：+ Title（`pallastrade_text_field`，placeholder）/ Description（`pallastrade_text_area`）
5. `tables.rb`：+ `title` 列（position 5，default，sortable，filterable）；原列 position 顺延
6. `en.yml`：+ `admin.redirects.title`/`description` 相关 label/help
7. spec：factory + admin UI（表单/列表）+ admin API（创建/返回）
8. api-docs admin.yaml：Redirect schema + title/description
9. skill/admin + scenarios GS-028 同步

## 列表列调整（tables.rb）

- title: position 5（最前，默认显示）
- from_path: 10 → 20
- to_path: 20 → 30
- status_code: 30 → 40
- active: 40 → 50

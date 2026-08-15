# REQ-20260815-redirects-intro-copy

> 关联 PRD：PRD-20260815-storefront-redirects-管理页面增加功能说明文案（approved）
> 任务：TASK-20260815035834-4eb9bea5

## Step 0：跨层搜索（已执行，结论见 PRD §6）

| 层 | 搜索路径 | 搜索关键词 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App | `backend/app/` | redirects/intro/说明 | 无 | 否 |
| Core | `pallastrade_gems/pallastrade_core/app/` | redirect | `redirect.rb`（模型已有） | 否 |
| API | `pallastrade_gems/pallastrade_api/app/` | redirect | `redirects_controller.rb` x2 | 否 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | intro/说明 | `option_types/index.html.erb`（`page_alerts`+`intro_help` 先例）；`redirects/*.html.erb` | ✅ 复用先例 |
| Storefront | `storefront/src/` | redirect | `lib/pallastrade/middleware.ts` | 否 |
| Platform | `platform/packages/` | redirect | 仅文档 | 否 |

**搜索结论**：Admin 层已有 `page_alerts` + `intro_help` 先例（option_types），直接复用；本次仅改 redirects 视图 + locale。

## Step 1：Skill 文件咨询

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：Admin 视图类改动走"直接修改 Admin Gem views"（第 8 优先级路径），不引入 decorator/subscriber |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | `PallasTrade::Admin::FormBuilder` 提供 `pallastrade_*` 表单 helper；列表页可用 `content_for(:page_alerts)` + `alert-info` 提供页面级说明（option_types 先例） |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已读 | Redirect 属 SEO 能力（catalog 域），管理端在 Developers → Redirects |

**按需 Skill：** 本次仅改 Admin 视图 + locale，无 API/模型/事件/前端变化，不涉及其他 skill。

## 实施内容

1. `redirects/index.html.erb`：+ `content_for(:page_alerts)` 信息框（`admin.redirects.intro_help`）
2. `redirects/_form.html.erb`：顶部 + 填写说明信息框（`admin.redirects.form_intro`）
3. `redirects/new.html.erb` / `edit.html.erb`：如需要调整布局以容纳信息框（默认由 new_resource partial 渲染 _form，无需改）
4. `en.yml`：+ `admin.redirects.intro_help` / `admin.redirects.form_intro`
5. `spec/requests/pallastrade/admin/redirects_spec.rb`：+ 文案断言

## 文案（用户已确认）

**index intro_help**：Redirects 让旧链接自动跳转到新链接。当商品改名、网址变化或下架时，访客点旧链接会看到"页面不存在"（404）。创建一条重定向后，旧链接会自动跳到新页面，访客不会迷路，Google 等搜索引擎也能把原来的排名权重转移给新链接。

**form_intro**：填一条规则：旧路径（From Path）→ 新路径（To Path）。例如商品从 /old-shaver 改名为 /new-shaver，就填 From Path = /old-shaver、To Path = /new-shaver，之后访客访问旧地址会自动跳到新地址。状态码选 301（永久搬家，推荐）或 302（临时跳转）。

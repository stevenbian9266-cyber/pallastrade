# REQ-20260727 — 产品编辑页分类选择优化

## Step 0：跨层搜索结果

| 层 | 搜索路径 | 搜索关键词 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| Admin Gem | `.../products/form/_categorization.html.erb` | categorization | 已有区块，多选模式 | 部分 — 需改交互 |
| Admin Gem | `.../products/form/_base.html.erb` | name | name 字段已存在 | ✅ |
| Admin Gem | `.../products/form/_form.html.erb` | layout | 整体布局文件 | 可覆盖 |
| Admin Gem | `.../taxons_controller.rb` | select_options | 下拉数据源端点 | ✅ |
| Core Gem | `.../taxon.rb` | nested_set, depth | acts_as_nested_set + depth 列 | ✅ 天然支持三级 |
| App | `backend/app/views/` | — | 空 | 需新建覆盖 |

**搜索结论**：已有 Categorization 区块、Name 字段、nested_set 数据模型。只需覆盖视图调整布局和交互。

## 需求描述

在 Admin 产品添加/编辑页面中：
1. 将 Categories 区块从右侧栏移到 Name 字段上方（主内容区顶部）
2. Category 改为**单选**（当前是多选）
3. 选择器改为**三级联动下拉**：先选一级 → 显示该级下的二级 → 显示该级下的三级
4. Category 为**必填**

## 任务类型

功能优化

## 技术方案

- **扩展层级**：Priority 6 — Decorator（覆盖 Admin View）
- **方式**：在 `backend/app/views/pallastrade/admin/products/` 目录下创建同路径文件，Rails 视图解析自动优先使用应用层文件
- **覆盖文件**：
  - `_categorization.html.erb` → 重写为三级联动单选
  - `_form.html.erb` → 调整布局，将 categorization 移到 base 上方

## 三元组清单

- [ ] Skill 更新：`pallastrade-admin` — 补充视图覆盖示例
- [ ] Eval 场景：GS-012（Admin 视图覆盖 — 分类选择器优化）
- [ ] 视图覆盖验证：确认分类区块在 name 上方、单选、三级联动

## 不可做清单

- [ ] 不修改 gem 源码（走视图覆盖）
- [ ] 不修改 Controller（已有 select_options 端点）
- [ ] 不修改 Model（nested_set 已支持三级）

## 决策节点

> ⏸️ **请确认以上理解。确认后我将输出详细方案文档。**

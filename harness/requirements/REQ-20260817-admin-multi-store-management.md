# 需求文档：多店铺管理（店铺列表/新建/切换）

- 关联 PRD：PRD-20260817-admin-多店铺管理-店铺列表-新建-切换（approved）
- 任务：TASK-20260817055059-114434b5
- 分支：dev

---

## Step 0：跨层搜索（6 层，gate 强制）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | store_selector / switch_store / Store.all / stores_path | 无 | 不涉及 |
| App — views/decorators | `backend/app/` | 同上 | 无 | 不涉及 |
| Core Gem — models | `pallastrade_core/app/models/` | Store / Current / RoleUser | `store.rb`（`has_prefix_id`、`default`、`after_create :create_default_policies`、`self.current`→`Current.store`）、`current.rb`（每请求 store 上下文）、`role_user.rb`（user↔role↔resource=store） | **复用**：数据层已完备 |
| Core Gem — services | `pallastrade_core/app/` | Store 创建 | `finders/stores/find_default.rb` | 复用（默认店铺解析） |
| API Gem — controllers | `pallastrade_api/app/controllers/` | for_store / current_store | 各 controller 均 `current_store.xxx` / `for_store` | 不涉及（作用域复用） |
| Admin Gem — controllers | `pallastrade_admin/app/controllers/` | stores / switch | `stores_controller.rb`（仅 edit/update）、`role_users_controller.rb`（按 current_store 授权） | **本次改造对象**（index/new/create/switch） |
| Admin Gem — views | `pallastrade_admin/app/views/` | store_dropdown / stores | `shared/sidebar/_store_dropdown.html.erb`（非切换器）、`stores/`（仅 edit） | **改造对象**（切换器 + 列表/新建） |
| Storefront | `storefront/src/` | store_selector / multi-store | 无 | 不涉及 |
| Platform | `platform/packages/` | storeId / StoreProvider | `dashboard`（React 6.0）`/$storeId` + `StoreProvider`/`useStore()` 已多店铺 | 仅参考（当前生产为 Rails admin） |

### 搜索结论

- 数据/作用域/授权层多店铺**已完备**（无重复）；改造集中在 **Admin 层**：`stores_controller` 补 index/new/create、新增 switch 路由 + base_controller session 解析、`_store_dropdown` 改切换器、Ability 补 store 管理权限。

---

## Step 1：Skill 文件咨询

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | "Add a menu item / nav entry to the admin → `PallasTrade.admin.navigation.sidebar.add` → **pallastrade-admin**"；Settings UI 属 admin 层定制，本次走 admin 扩展。 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | "Context: `current_store`, `current_currency`, `try_pallastrade_current_user`"（视图上下文含 current_store）；"breadcrumb: 特殊 crumb 控制器声明 `self.skip_breadcrumb_derivation = true` 保留手写（stores 的 section 级）"；表单用 `preference_field_for` 渲染 store settings。 |
| `ai/skills/pallastrade-catalog/SKILL.md` | ⬜ 不涉及 | 本次为 admin 店铺管理，非商品目录。 |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ⬜ 不涉及 | ⬜ | 无接口变更 |
| `pallastrade-decorators` | ⬜ 不涉及 | ⬜ | |
| `pallastrade-dependencies` | ⬜ 不涉及 | ⬜ | |
| `pallastrade-events-webhooks` | ⬜ 不涉及 | ⬜ | |
| `pallastrade-storefront` | ⬜ 不涉及 | ⬜ | |
| `pallastrade-testing` | ⬜ 不涉及 | ⬜ | |
| `pallastrade-i18n` | ⬜ 不涉及 | ⬜ | 文案沿用 `PallasTrade.t('admin.stores.*')`（en + zh-CN） |

---

## 需求标题

多店铺管理：店铺列表 / 新建 / 切换。

## 任务类型

新功能（多店铺管理 UI）

## 需求描述

1. 后台店铺列表页（全部店铺 + 默认标记 + 搜索）。
2. 新建店铺（表单校验 + 初始化默认策略 + 自动授予当前超管 + 自动切换）。
3. 侧边栏店铺下拉改为切换器（列出用户可访问店铺，切换后 current_store 生效）。
4. 权限：店铺管理=超管；切换=RoleUser 授权；单店铺零回归。

## 影响范围（harness affected 输出）

实施时运行 `harness affected --base origin/main`；预期涉及：
- `pallastrade_admin`：stores_controller / base_controller / routes / _store_dropdown / stores 视图 / locales
- `backend/spec/requests/pallastrade/admin/stores_multi_spec.rb`
- `ai/skills/pallastrade-admin/SKILL.md`（知识同步）

## 技术方案（初步）

- `stores_controller.rb`：补 `index`/`new`/`create`（参数白名单参照 store 工厂：code/name/url/mail_from_address/customer_support_email/new_order_notifications_email/default_currency/supported_currencies/default_locale）；创建后授予当前用户 admin RoleUser（resource=store）+ 自动切换。
- 新增 `switch_store` 动作：POST `store_id` → 校验 RoleUser 授权 → `session[:admin_store_id]` → 重定向回原页。
- `base_controller.rb`：`current_store` 解析 = session 选中店铺（授权校验）→ 用户首个可访问店铺 → `PallasTrade::Current.store`。
- 路由：`resources :stores, only: [:index, :new, :create, :edit, :update]` + `post 'switch_store'`。
- 视图：`stores/index.html.erb`（Ransack 表格）+ `stores/new.html.erb`；`_store_dropdown.html.erb` 改切换器。
- 授权：Ability 对 `PallasTrade::Store` manage（SuperUser 已覆盖）；切换校验 RoleUser。
- 无 DB 迁移；无 API 变更。

## 风险点

- 最高风险：session 切换店铺后数据作用域错乱 → 每请求重校验 RoleUser 授权 + 回退逻辑；单店铺回归保护。
- 回滚难度：低（单次提交，可 revert）。

## 决策节点

✅ 用户已确认（"实施"）。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| Ruby 控制器/路由 | `stores_controller.rb`、`base_controller.rb`、`routes.rb` | `rspec stores_multi_spec.rb` + admin 回归 | | ⬜ |
| 视图 | `stores/**`、`_store_dropdown` | 请求 spec 断言渲染 | | ⬜ |
| 全部 | — | `harness check --profile quick` | | ⬜ |
| UI | 列表/新建/切换 | 浏览器 E2E（dev 部署后） | | ⬜ |

### 验证结论

（实施后填写）

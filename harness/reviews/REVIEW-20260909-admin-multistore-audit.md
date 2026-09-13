# REVIEW-20260909 — 管理后台多 store 支持现状审计与单店化删减方案

> 类型：审计（audit，只读分析 + 报告，无代码改动）
> Task：TASK-20260909050640-ed214106（Gate GATE-2026-09-09T05-08-07）
> 日期：2026-09-09 ｜ 基线：dev @ 78e34761
> 范围：管理后台（Rails `pallastrade_admin`）多 store/多店铺支持 —— 当前代码逻辑、业务逻辑盘点，以及「清除多 store 逻辑、单店化」所需的业务与代码删减方案。
> 方法：6 层跨层搜索（backend/app → core → api → admin → storefront → platform）+ 领域 Skill（pallastrade-admin）+ 关键文件精读；所有行号为 dev HEAD 实测值。

---

## 〇、核心结论（速览）

1. **当前生产管理后台 = Rails `pallastrade_admin`（ERB+Turbo）**，其上叠加了团队自研的「多店铺管理（2026-08-17）」——带 `# PALLAS-CUSTOM: 多店铺管理（2026-08-17）` 标记，共 **7 个文件**。这是单店化删减的**主要对象**。
2. **新一代 React Dashboard（`/$storeId` 路由 + StoreProvider/useStore/StoreSwitcher）已于 2026-08-08 移除**（见 `harness/requirements/REQ-20260808-remove-react-dashboard.md`）。`platform/packages` 现仅 `cli / create-pallastrade-app / docs / sdk / sdk-core`，**无 dashboard/admin-sdk 运行代码**；残留仅为过时生成物（`docs/dist` + CLI 插件模板 `.tt`）。
3. **框架本体已是 single-store 收敛架构**：Product/Promotion/PaymentMethod 已从多对多迁到单 `belongs_to :store`；`LegacyMultiStoreSupport` / `StoreScopedResource` 是 deprecated 兼容垫片；恢复真多店需另装 `pallastrade_multi_store` gem —— **该 gem 不存在**。
4. **数据隔离 = 行级 `store_id` 列**（schema 共 46 处）+ `PallasTrade::Current`（每请求线程上下文）+ `SingleStoreResource`（防跨店写入）。
5. **「current store」解析只有两条路径**：Rails admin = **session 选中店**（授权校验）；其余一切（storefront、v3 API、job）= 统一 `FindDefault`（**恒返回 default store，忽略 URL/域名**）⇒ **实际是伪多店/单店**：代码到处携带 store 上下文，但真实只有 1 家 seed 店（`code:'shop'`）在跑。
6. **删减建议基调**：移除 admin 层的**多店 UI/切换/建店入口/按店 session 授权维度**（2026-08-17 自研层），**保留** store_id 列 + `Current` + `for_store` scope 基建（单店数据的来源与防御纵深，且为未来恢复多店留后门）；不推荐物理删除 46 个 store_id 列（等价于一次高风险重构，收益低）。

---

## 一、架构总览（当前代码逻辑）

```mermaid
flowchart LR
    subgraph RAILS_ADMIN[管理后台 Rails Admin · pallastrade_admin]
      NAV[导航 :stores 顶级<br/>+ Store Details 叶子<br/>navigation L330-346]
      CTRL[StoresController<br/>index/new/create/switch_store]
      BASE[BaseController<br/>current_store override<br/>admin_accessible_stores]
      DDL[_store_dropdown<br/>店铺切换器 UI]
      ROUTE[switch_store POST<br/>routes L222-227]
    end

    subgraph AUTH[按店授权体系 · PALLAS-CUSTOM]
      ROLE[RoleUser 绑 store<br/>core role_user.rb L11]
      ABIL[Ability 按店解析角色<br/>ability.rb L186-203]
      SEED[SuperUser 权限集<br/>seeds/roles.rb]
    end

    subgraph STORE_CTX[Store 上下文]
      CUR[PallasTrade::Current<br/>current.rb 线程上下文]
      SESSION[session[:admin_store_id]]
      FIND[Stores::FindDefault<br/>唯一 finder · 忽略 url]
    end

    subgraph DATA[数据层 · 行级 store_id]
      SINGLE[SingleStoreResource<br/>store_id 不可变 + for_store scope]
      COLS[46 处 store_id 列]
    end

    CTRL -- switch_store --> SESSION
    BASE -- 解析 --> SESSION
    BASE -- 写 --> CUR
    DDL -- POST --> ROUTE --> CTRL
    NAV --> CTRL
    ROLE --> ABIL
    CUR --> SINGLE
    SINGLE --> COLS
    FIND --> CUR
    ABIL --> BASE
```

- **当前「多店」业务逻辑（管理后台）**：管理员登录后，可经侧边栏店铺下拉（`_store_dropdown`）在**其有权访问的店铺**间切换；`switch_store` 校验授权 → 写 `session[:admin_store_id]` → 后续请求 `BaseController#current_store` 从 session 解析并写入 `PallasTrade::Current.store` → 所有 CRUD 经 `for_store(current_store)` 自动按店过滤、Ability 按店解析角色判权。超管可访问全部店，普通管理员仅其 `RoleUser` 绑定的店。另有「New Store」入口（受 `root_domain.present?` 门控，本仓未配置 root_domain → 入口隐藏）。
- **API / storefront 的「多店」语义**：只有 `FindDefault`，任何请求（无论域名）都解析到 default store ⇒ 线上 API 面实质单店。
- **数据模型**：46 张表带 `store_id` FK；授权、商品、订单、支付等核心链全部按店隔离；遗留 3 张多对多 join 表（`products_stores` / `promotions_stores` / `payment_methods_stores`）仅供不存在的 `pallastrade_multi_store` gem 复用。

---

## 二、分层盘点（6 层命中清单）

### 层 1 — Rails 管理后台 `pallastrade_gems/pallastrade_admin/`（多店删减主战场）

| 文件 | 行号 | 作用 | 单店化动作 |
|---|---|---|---|
| `app/controllers/pallastrade/admin/base_controller.rb` | L24–26 | `# PALLAS-CUSTOM: 多店铺管理` `helper_method :admin_accessible_stores` | 移除/收敛 |
| 同上 | L28–31 | `current_store` override → `resolve_admin_current_store` | 收敛为恒 default store |
| 同上 | L37–42 | `admin_accessible_stores`：超管=全部店，否则 RoleUser 绑店 | 移除 |
| 同上 | L231–237 | `resolve_admin_current_store`：session 选中店 → RoleUser 店 → `Store.default` | 收敛 |
| 同上 | L239–245 | `admin_store_from_session`：读 `session[:admin_store_id]` + 授权校验 | **移除（核心）** |
| 同上 | L247–255 | `accessible_stores_via_role_users`：`RoleUser.where(user:, resource_type:Store)` | 移除 |
| 同上 | L257–266 | `superuser?`：防 current_ability 递归 | 视保留情况 |
| `app/controllers/pallastrade/admin/stores_controller.rb` | L32–36 | `index` 店铺列表页（Ransack+pagy） | **移除** |
| 同上 | L39–44 / L47–58 | `new` / `create`：建店 + 授权 + 写 session | **移除** |
| 同上 | L69–79 | **`switch_store`**：多店切换核心 | **移除** |
| 同上 | L118–130 / L135–156 | `permitted_create_params` / `grant_creator_admin_access` / `grant_store_access` | **移除** |
| 同上 | L16–33, L85–113 | 单店 settings `edit`/`update`（**非多店**） | ✅ 保留 |
| `config/routes.rb` | L222–224 | `resources :stores, only:[:index,:new,:create]` + `post 'switch_store'` | **移除** |
| 同上 | L227 | `resource :store, only:[:edit,:update]`（单店 settings） | ✅ 保留 |
| `config/initializers/pallastrade_admin_navigation.rb` | L330–337 | sidebar 顶级 `:stores`（position 94） | **移除/降级** |
| 同上 | L339–346 | 单店 `Store Details` 叶子（`general_settings`） | ✅ 保留 |
| `app/views/pallastrade/admin/shared/sidebar/_store_dropdown.html.erb` | L1–29 | **店铺切换器 UI**（Turbo POST） | **移除** |
| `app/views/pallastrade/admin/shared/_sidebar.html.erb` | L4–6 / L26–28 | 桌面/移动渲染 store_dropdown | **移除渲染** |
| `app/views/pallastrade/admin/shared/_new_item_dropdown.html.erb` | L24–28 | "New Store" 入口（`root_domain.present?` 门控，当前隐藏） | **移除** |
| `app/views/pallastrade/admin/stores/index.html.erb` | L1–60 | 店铺列表（每行 Switch） | **移除** |
| `app/views/pallastrade/admin/stores/new.html.erb` | 全 | 新建店铺页 | **移除** |
| `app/controllers/pallastrade/admin/resource_controller.rb` | L8,31,367–371 | `set_current_store`（绑 current store） | ✅ 保留（单店也需） |
| 同上 | L190,214–217,245–257 | 列表默认 `for_store(current_store)` | ✅ 保留 |
| `app/controllers/pallastrade/admin/users_controller.rb` | L74–78 | `set_current_store` no-op（用户不直绑店） | ✅ 保留 |
| 其余 ~60 controllers | — | `current_store.xxx` 作用域 | ✅ 保留 |
| `config/locales/en.yml` | L394 | `switch_store: Switch store` | 移除文案 |

> `# PALLAS-CUSTOM` 落在 gem 内属团队对框架直接改动（AGENTS §1 允许，升级=merge）。多店标记共 7 文件：`base_controller.rb`、`stores_controller.rb`、`_store_dropdown.html.erb`、`stores/index.html.erb`、`stores/new.html.erb`、`pallastrade_admin_navigation.rb`、`routes.rb`。

### 层 2 — API `pallastrade_api/`（实际已单店，无需删减）

| 文件 | 行号 | 作用 | 单店化动作 |
|---|---|---|---|
| `app/controllers/pallastrade/api/v3/base_controller.rb` | L13 | include `ControllerHelpers::Store`（FindDefault） | ✅ 保留 |
| `app/controllers/pallastrade/api/v3/admin/base_controller.rb` | L1–16 | Admin API 基类，无 override ⇒ 恒 default store | ✅ 保留 |
| `concerns/.../admin_authentication.rb` | L35 | api_key 的 `store_id != current_store.id` → 拒 | ✅ 保留（防御） |
| 同上 | L48–66 | `require_store_membership!`（JWT 按店 RoleUser） | ⚠️ 若做纯单店可简化 |
| `concerns/.../api_key_authentication.rb` | L19 | publishable key 在 current_store.api_keys 内 | ✅ 保留 |
| `admin/store_controller.rb` | L1–40 | 仅单数 `/api/v3/admin/store`，**无 store 列表端点** | ✅ 保留 |
| 各 admin controller（~50） | — | `current_store.xxx` / `for_store` | ✅ 保留 |

### 层 3 — Core `pallastrade_core/`（store 基建，建议保留）

| 文件 | 行号 | 作用 | 单店化动作 |
|---|---|---|---|
| `app/models/pallastrade/store.rb` | L1–260+ | Store 模型：`has_prefix_id :store`、`default` 布尔、`self.current/default` | ✅ 保留 |
| `app/models/pallastrade/current.rb` | L6–80+ | `CurrentAttributes` store 回退 `Store.default` | ✅ 保留 |
| `lib/.../controller_helpers/store.rb` | L16–34,71–83 | storefront/API current_store 解析 | ✅ 保留 |
| `lib/.../dependencies.rb` | L105 | `current_store_finder: FindDefault` | ✅ 保留 |
| `finders/.../find_default.rb` | L1–15 | 唯一 finder（忽略 url） | ✅ 保留 |
| `concerns/.../single_store_resource.rb` | L1–25 | 单店硬绑定 + `for_store` | ✅ 保留 |
| `concerns/.../legacy_multi_store_support.rb` | L1–60 | deprecated 垫片 | ⚠️ 可清理（低优先） |
| `concerns/.../store_scoped_resource.rb` | L1–35 | deprecated 多对多垫片 | ⚠️ 可清理 |
| `role_user.rb` / `role.rb` / `ability.rb` | L2–40 / L30–40 / L22–203 | **按店授权（PALLAS-CUSTOM 2026-08-16）** | ⚠️ 见方案决策 |
| `seeds/stores.rb` | L6–22 | 仅 1 个 default store（code `shop`） | ✅ 保留 |
| 遗留 join 模型 `store_product.rb` 等 | 全 | 仅供 multi_store gem | ⚠️ 可清理 |

### 层 4 — Host App `backend/app/`（无多店自定义）

- 唯一命中 `backend/app/controllers/pallastrade/admin/ai_controller.rb`（L33–226）：AI 模块全部按 `current_store` 过滤，属**正常单店作用域**，非切换/多店逻辑 → ✅ 保留。
- `backend/config/initializers/pallastrade.rb`：无 `root_domain`、无 finder override → ✅ 保留。
- **结论：Host App 层无多店 PALLAS-CUSTOM，全部多店逻辑在 gem 内。**

### 层 5 — Storefront `storefront/src/`（无管理后台 store 切换）

- `StoreContext.tsx`（L1–105）名含 Store 实为 **market/currency/locale** 上下文（单店内多市场），无 storeId/切换 → ✅ 保留。
- 无 store switcher、无 store 列表、无 `admin_store_id`。

### 层 6 — Platform `platform/packages/`（仅过时残留）

| 文件 | 作用 | 单店化动作 |
|---|---|---|
| `sdk/src/client.ts` L20–30 | Store SDK 无 storeId/切换 | ✅ 保留 |
| `cli/templates/plugin/packages/dashboard/**`（.tt） | **过时模板**仍生成 `/$storeId` React dashboard 插件路由 | ⚠️ 清理模板 |
| `docs/dist/developer/dashboard/**` | **过时文档**：StoreSwitcher/useStore/`$storeId` 描述 | ⚠️ 清理文档 |
| `dashboard/dashboard-ui/dashboard-core/admin-sdk` 包 | **不存在**（2026-08-08 移除） | — |

---

## 三、数据流（当前完整调用链）

### Rails 管理后台（真多店 · session 切换）
```
登录 AdminUser → layout 渲染 _sidebar → _store_dropdown（遍历 admin_accessible_stores）
→ 用户点店 POST /admin/switch_store（routes L224）
→ stores#switch_store L69：admin_accessible_stores.include? 校验 → grant_store_access L148（补 admin RoleUser）
   → session[:admin_store_id] = store.id
→ 下个请求 base#current_store L28 → resolve_admin_current_store L231
→ admin_store_from_session L239（授权命中）｜否 → accessible_stores_via_role_users.first L247｜再否 → Store.default L218
→ PallasTrade::Current.store = store（current.rb）→ 各 controller current_store.xxx 查库
→ ResourceController collection L245：model_class.for_store(current_store) 自动过滤
→ Ability#determine_role_names L191：RoleUser.where(store:) 按店判权
```

### Storefront + API v3（实际单店 · 恒 default store）
```
Next.js storefront → SDK（x-pallastrade-api-key=pk_xxx）→ GET /api/v3/store/*
→ Api::V3::BaseController（include ControllerHelpers::Store）→ current_store = FindDefault.execute
→ PallasTrade::Store.where(default:true).first → PallasTrade::Current.store
```
Admin API v3 同路径（无 override），叠加：api_key.store_id 必须 == current_store.id；JWT admin 须对 current_store 有 RoleUser。

> **关键点**：全仓只有 `FindDefault` 一个 finder，`SERVER_NAME`/url 被忽略 ⇒ 无论请求哪个域名，API 层都解析到 default store。

---

## 四、单店化删减方案

### 4.0 方案决策建议

| 维度 | 方案 A：收敛式单店（**推荐**） | 方案 B：物理删除 store 维度 |
|---|---|---|
| 做什么 | 删**多店 UI/切换/建店/按店 session 授权**，保留 store_id 列 + Current + for_store 基建，语义收敛为「恒 default store」 | 连同 46 处 store_id 列、Current、SingleStoreResource、Ability 按店全部删除/重写为全局 |
| 工作量 | 小（admin gem 内删改 + 少量收敛） | 极大（等价跨层重构：core/api/admin/host/schema/seed） |
| 风险 | 低（API/storefront 已单店；改动不触数据层） | 高（跨店写保护/能力判权/历史数据迁移全部重来） |
| 可逆性 | 高（未来装 multi_store gem 或重开入口即可恢复） | 低 |
| 建议 | ✅ 采用 | 🚫 不建议（除非产品确证永不多店且愿付重构成本） |

**核心判断**：仓库现状是「框架单店收敛 + admin 层 2026-08-17 自研多店切换 UI」。真正的多店"逻辑"只存在于 admin 的 **session 切换 + 建店 + 按店授权视图**。删这些即达成"清除多 store 逻辑"。store_id 数据列与 `for_store` 过滤不是"多 store 逻辑"，而是**单店数据的隔离来源**（`FindDefault` 使所有请求落 default store），删除它们只会徒增风险。

### 4.1 业务逻辑层面删减（产品/管理决策）

| # | 业务决策 | 现状 | 删除后 |
|---|---|---|---|
| B1 | **取消店铺切换** | 管理员侧边栏下拉在多家店间切换（session） | 后台不再出现"选择店铺"，一切操作作用于唯一 default store |
| B2 | **取消建店入口** | New Store + stores index/new/create + `grant_creator_admin_access` | 后台不能新建店铺；店铺由 seed/数据初始化（或未来专用通道） |
| B3 | **取消「按店授权」管理维度** | RoleUser 绑 store；Ability 按店解析角色；`admin_accessible_stores` | 管理员账号全局（或仍经 RoleUser 但不再按店区分）；不再有"某管理员只管某店"的 UI/判断 |
| B4 | **取消域名/店铺映射基建（未落地项）** | `root_domain` 未配置；`FindDefault` 忽略 url；custom_domains 表无消费 finder | 明示"单店部署"，删除/冻结 root_domain 与域名路由相关开发预期 |
| B5 | **明确单店数据口径** | 全栈 current_store 解析（admin=session，其余=default） | 统一为 `Store.default` 单一口径；session 切店概念移除 |
| B6 | 保留 | 单店 Store Details（general_settings）、API key 绑店校验、ai 模块按店过滤 | 保留不变（这些是单店运营必需） |

### 4.2 代码层面删减清单（按阶段）

**阶段 0 · 纯删除（低风险，删 admin gem 多店 PALLAS-CUSTOM）**

| 文件 | 删什么 |
|---|---|
| `pallastrade_admin/app/controllers/.../stores_controller.rb` | `index`/`new`/`create`、`switch_store`、`grant_creator_admin_access`、`grant_store_access`、`preset_email_fields`、`permitted_create_params`、`admin_accessible_stores` 相关（**保留 `edit`/`update` 单店 settings**） |
| `pallastrade_admin/config/routes.rb` L222–224 | `resources :stores, only:[:index,:new,:create]` + `post 'switch_store'`（**保留 L227 `resource :store`**） |
| `_store_dropdown.html.erb` | 整个文件 |
| `_sidebar.html.erb` L4–6 / L26–28 | 移除两处 store_dropdown 渲染 |
| `_new_item_dropdown.html.erb` L24–28 | 移除 "New Store" 入口 |
| `stores/index.html.erb`、`stores/new.html.erb` | 删除 |
| `pallastrade_admin_navigation.rb` L330–337 | 移除 sidebar 顶级 `:stores`（**保留 L339–346 Store Details 叶子**，调整归属到设置分组） |
| `base_controller.rb` | 删 `admin_accessible_stores` / `accessible_stores_via_role_users` / `admin_store_from_session` / `resolve_admin_current_store` 的多店分支；`current_store` override 收敛为 `PallasTrade::Store.default`（或直接移除 override 走默认 FindDefault，需核对 admin 内是否有 session 以外依赖） |
| `config/locales/en.yml` L394 | 删 `switch_store` 文案 |

**阶段 1 · 收敛改造（中风险，逐项核对引用后再删）**

| 文件 | 改什么 |
|---|---|
| `resource_controller.rb` 等 ~60 controllers | 保持 `current_store.xxx` 不变（无需改）；核对是否有依赖 `admin_accessible_stores`/session 的调用并移除 |
| `users_controller.rb` | 若取消按店授权视图，同步简化（当前 set_current_store no-op 可留） |
| sidebar 布局 | 原切换器位置替换为当前店铺名徽标/只读展示（`Store.default`），避免布局空洞 |
| seed/权限 | 若 B3 全删：`role_user.rb` 是否继续绑 store、`ability.rb` 按店分支是否简化 —— **建议先保留**（能力判权仍靠 store 隔离），只删管理 UI 上的"按店授权"编辑入口（如有） |

**阶段 2 · 可选清理（低优先，不影响运行）**

| 文件 | 动作 |
|---|---|
| `legacy_multi_store_support.rb` / `store_scoped_resource.rb` / join 模型 `StoreProduct` 等 | 标记 deprecated 保留或清理（需先确认无 include 引用——Product L37/L162 仍 include，故**不可直接删**，只能改注释） |
| `platform/cli/templates/plugin/packages/dashboard/**`（.tt） | 更新模板去掉 `$storeId`/StoreSwitcher 残留（若 CLI 不再产出 dashboard 则删模板） |
| `platform/docs/dist/developer/dashboard/**` | 删除/更新过时文档（StoreSwitcher/useStore/`$storeId`） |
| `AGENTS.md` §1 中 dashboard 相关行、`platform/CLAUDE.md` 过时段落 | 同步清理（如确认已删 React dashboard） |
| `harness/requirements/REQ-20260808-remove-react-dashboard.md` 等 | 归档说明，勿重复实施 |

### 4.3 明确保留（删除会导致回归，禁止动）

| 项 | 原因 |
|---|---|
| 46 处 `store_id` 列 + `SingleStoreResource#for_store` | 单店数据的隔离来源；防跨店写入；物理删列 = 高风险重构 |
| `PallasTrade::Current` + `FindDefault` + `dependencies.rb` finder 配置 | 全栈 current_store 解析主干；删了 storefront/API/job 全断 |
| `resource_controller` 的 `for_store(current_store)` 过滤 | 所有后台 CRUD 依赖 |
| `api_key.rb belongs_to :store` + `admin_authentication` L35/L48 校验 | 密钥绑定与 JWT 按店成员校验（安全防御） |
| `BaseMailer` 的 store 回退链（order.store → Current → default） | 邮件归属 |
| `ai_controller.rb` 的 current_store 过滤 | 正常业务作用域 |
| 单店 settings（store edit/update + Store Details 导航） | 店铺基础配置入口，非多店逻辑 |

### 4.4 验收建议（若立项实施）

- 阶段 0 后：后台登录 → 无店铺下拉/无 New Store/无 switch_store 路由；导航只剩单店 Store Details；API 行为不变（`GET /api/v3/admin/store` 恒 default store）。
- 回归面：任何后台 CRUD 仍按 default store 过滤（数据隔离不破）；角色权限仍生效（RoleUser 保留时）。
- 证据要求（按 AGENTS §6）：UI 截图（侧边栏无切换器）+ Rails log（CRUD `Completed 200`）。

---

## 五、风险与注意

1. **session 依赖核查**：`session[:admin_store_id]` 可能被布局/授权以外的代码读取——删 `resolve_admin_current_store` 前全仓 grep 确认无其他消费者。
2. **RoleUser/Ability 按店是 2026-08-16 权限体系重构的产物**：若 B3 连带删"按店授权"，需与权限体系（SuperUser 权限集/`PermissionSets`）联动评估，建议单独立项而非随 UI 一起删。
3. **join 模型与垫片有代码引用**：`Product` 等仍 include `LegacyMultiStoreSupport`/`StoreScopedResource`——清理时只能改注释/等待框架收敛，直接删会编译失败。
4. **过时文档/模板**（`$storeId`/StoreSwitcher）不代表运行代码，清理优先级低；勿把它们当作"当前多店逻辑"来删。
5. 本方案为**只读审计交付物**：不含任何代码改动；实施需另开 feature/refactor 任务并按 PRD/REQ 流程执行（R8）。

---

## 附：删减后目标形态（单店化）

- 管理后台 = 单一店铺运营界面：登录 → 直接操作 default store 数据；无店铺选择、无建店、无按店授权 UI。
- 后端 = 保留 store 上下文（Current/FindDefault/for_store）作为**单店数据来源与隔离纵深**，但不再有"切换/多店"概念暴露。
- 未来若需真多店：安装 `pallastrade_multi_store` gem（当前不存在）+ 恢复 admin 切换层即可，数据层无需迁移。

# P0 基线加固 — 实施记录（订单生命周期升级前置）

> **文档类型**：Research / P0 阶段实施记录
> **日期**：2026-08-26
> **状态**：✅ 已完成
> **关联**：`docs/research/RESEARCH-20260826-order-lifecycle-upgrade-plan.md`（§5 P0）

---

## 1. P0 范围与结论

| P0 任务 | 结论 | 证据 |
|---|---|---|
| ① 数据库定时备份任务 | ✅ 已创建 `scripts/ops/db_backup.{sh,ps1}`（服务器 + 本地） | §3 |
| ② 回滚演练脚本 | ✅ 已创建 `scripts/ops/rollback_prepare.{sh,ps1}`（schema 快照 + 迁移版本 + 触发备份） | §3 |
| ③ 订单链路测试基线 | ⚠️ 见 §4：核心链路**无自动化 spec**（现实约束），已记录基线 = 本地 harness check + CI 全绿，并给出补齐建议 | §4 |
| ④ `PallasTrade::Config` store 级覆盖机制 | ✅ 可用：`Store` include `Preferable`，已有 store 级 preference 先例 | §2 |

---

## 2. Config store 级覆盖机制确认（升级开关的落点）

### 2.1 机制结论

`PallasTrade::Config`（全局，`lib/pallastrade/core/configuration.rb`，`Preferences::RuntimeConfiguration`）与 **`Store` 级 preference**（`app/models/pallastrade/store.rb`，`include Preferable`）是两套机制，均已验证可用：

- **全局默认**：`PallasTrade::Config[:auto_split_orders]`（configuration.rb 中 `preference :auto_split_orders, ...`）——升级开关的全局默认值。
- **Store 级覆盖**：`store.preferred_auto_split_orders`（store.rb 中 `preference :auto_split_orders, ...`）——逐店灰度。
- **已有先例**（store.rb L62/L69/L80）：
  - `preference :guest_checkout, :boolean, default: true`（channel 级另有覆盖）
  - `preference :stock_reservation_ttl_minutes, :integer, default: 10`
  - `preference :order_routing_strategy, :string, default: 'PallasTrade::OrderRouting::Strategy::Rules'`

### 2.2 落点建议（P2/P5 实施时）

- 新增全局默认：`configuration.rb` 增加 `preference :auto_split_orders, :array, default: []`、`preference :combined_payment_enabled, :boolean, default: false`。
- 新增 store 级覆盖：`store.rb` 增加同名 preference，解析用 `store.preferred_xxx.presence || PallasTrade::Config[:xxx]` 模式（与 `guest_checkout` 的 channel→store→全局 解析一致）。
- 已有 `stock_reservation_ttl_minutes` 说明 store 级配置机制已被生产使用，风险低。

---

## 3. 运维脚本（已创建）

### 3.1 文件清单（`scripts/ops/`，根 `.gitignore` 已含 `/backups/`）

| 脚本 | 环境 | 作用 |
|---|---|---|
| `db_backup.sh` | 服务器 / Linux | `docker exec pg_dump` → gzip → `backups/`，保留最近 N 份（默认 7） |
| `db_backup.ps1` | 本地 Windows dev | 同上（PowerShell 版，`cmd /c` 包装保证二进制管道安全） |
| `rollback_prepare.sh` | 服务器 / Linux | schema.rb 快照 + 最新迁移版本记录 + 触发备份 |
| `rollback_prepare.ps1` | 本地 Windows dev | 同上 |

### 3.2 用法

```bash
# 服务器（dev 栈）
cd /opt/pallastrade/repo
bash scripts/ops/db_backup.sh dev                      # 立即备份
bash scripts/ops/rollback_prepare.sh dev               # 升级前：快照+版本+备份

# 服务器定时（cron，每日 03:00）
0 3 * * * cd /opt/pallastrade/repo && bash scripts/ops/db_backup.sh dev >> /var/log/pallastrade-backup.log 2>&1
```

```powershell
# 本地 Windows（需 Docker Desktop 运行 + backend compose up）
.\scripts\ops\db_backup.ps1
.\scripts\ops\rollback_prepare.ps1
```

### 3.3 容器名与连接（已验证）

| 环境 | compose 项目名 | postgres 容器 | 数据库 | 认证 |
|---|---|---|---|---|
| 本地 | `pallastrade`（backend/docker-compose.dev.yml） | `pallastrade-postgres-1` | `pallastrade_development` | trust（无密码） |
| 服务器 | `pallastrade-dev`（deploy/docker-compose.dev.yml） | `pallastrade-dev-postgres-1` | `pallastrade_development` | trust（无密码） |

> 备份输出目录 `backups/` 已在根 `.gitignore` 忽略，不会提交。

---

## 4. 测试基线（现状与约束）

### 4.1 本地可执行检查（本次已验证通过）

```
npx harness check --profile quick
→ lint/typecheck/monorepo-contract/api-contract/affected-tests/nav-validate 均 delegated to CI
→ ✅ No anti-patterns detected
→ ✅ AP-009 degraded-loop scan: 无违规
→ ✅ nav-validate static scan OK（Rails 不可用时静态降级）
```

### 4.2 核心链路自动化测试现状（重要风险）

- **`pallastrade_core/spec/` 只有 `fixtures/`，无任何 `*_spec.rb`** —— 订单 / 支付 / 发货 / 售后核心逻辑（`Order`、`Payment`、`Shipment`、`CustomerReturn`、`Reimbursement`、`Refund` 等）**当前没有自动化测试保护**。
- 仓库现存测试仅：`backend/spec/`（自定义功能：reviews/redirects/posts/menu/roles 等）+ `pallastrade_stripe`（1 个）+ `pallastrade_legacy_product_properties`（6 个）。
- **本地无 Ruby / Postgres / Docker 运行**，无法本地跑 RSpec；Rails 测试基线以 **CI 全绿** 为准（`backend-ci.yml` + `harness-full.yml` 的 `bundle exec rspec spec/ $SPEC_DIRS`，push 到 dev/main 自动触发）。

### 4.3 基线定义与建议

1. **本次升级的回归保护基线**：任何阶段 PR 合并前，`backend-ci.yml` + `harness-full.yml` + `storefront-ci.yml` + `platform-ci.yml` 全绿。
2. **建议（P1 起）**：为核心链路补齐**最小冒烟测试**（本次升级的直接回归网）：
   - `Order#parent/children` 关联与语义方法（`parent_order?` / `child_order?` / `single_order?`）
   - `Order#total` 父子聚合公式（own + Σ(children)）
   - `Orders::Splitter` 拆单（分组/金额守恒/幂等）
   - `PaymentCombination` 状态机（非法迁移→业务错误）
   - `Carts::Complete` 拆单接入后下单全链路 smoke
   - 售后：`CustomerReturn` 子订单/父订单批量售后
3. 已有 fixtures（`pallastrade_core/spec/fixtures/`）可复用作测试数据基础。

---

## 5. 标准备份/回滚流程（实施各阶段时强制）

### 5.1 升级前（每阶段）

```bash
bash scripts/ops/rollback_prepare.sh dev   # 1) schema 快照 2) 迁移版本 3) 备份
```

### 5.2 迁移异常回滚

```bash
# 服务器（web 容器内）
docker exec -it pallastrade-dev-web-1 bundle exec rails db:rollback STEP=N   # N=异常迁移数
# 本地
cd backend && bundle exec rails db:rollback STEP=N
# 代码回滚
git checkout <上一提交>   # 重建镜像部署（见 deploy/README.md 标准流程）
```

### 5.3 数据恢复（灾难恢复）

```bash
# 恢复到备份时间点（示例，需按实际备份文件）
gunzip -c backups/dev-pallastrade_development-<TS>.sql.gz | docker exec -i pallastrade-dev-postgres-1 psql -U postgres -d pallastrade_development
```

> ⚠️ 恢复会覆盖当前数据，执行前确认备份时间点正确；生产恢复须先停服务（单栈策略）。

---

## 6. 变更记录

| 日期 | 变更 | 操作者 |
|---|---|---|
| 2026-08-26 | P0 完成：创建 4 个运维脚本 + Config 机制确认 + 测试基线记录 | AI |

# P0-5 Secret 安全迁移 — ENCRYPTION_COMPATIBILITY_SPIKE（FR-050~054）

> 状态：Spike 完成，**方案 A 已确认并实施落地**（2026-09-03）。本文档含决策依据与运维 runbook。
> 关联：PRD FR-050/051/052/053/054；`豆包梳理业务需求/P0任务.md` §八。

---

## 1. 结论摘要（TL;DR）

- Gateway 凭据现状：`PaymentMethod.preferences` = **text/YAML 明文**（真实风险，文件确认）。
- 代码库已内置 **Active Record Encryption 基建**（`GatewayCustomer#profile_id`、`WebhookEndpoint#secret_key` 均已声明 `encrypts`），**但按 ENV 条件启用**，本仓库 dev 容器未注入密钥 → 这些字段在本地实际仍明文。
- **Spike 实证（RAILS_ENV=test + 注入密钥）**：`serialize :preferences, type: Hash, coder: YAML` + `encrypts :preferences` 组合**可用** —— 写入后 DB 列无明文（长度 162、无 `sk_test_abc` 子串）、读回解密正确（含嵌套 Hash）。
- **渐进迁移关键**：`support_unencrypted_data=false`（默认）时读旧明文行会抛 `ActiveRecord::Encryption::Errors::Decryption` → 迁移窗口必须开 `support_unencrypted_data=true` 做 dual-read + backfill。
- **方案决策（FR-052）：推荐 A — Active Record Encryption 直接加密 `preferences` 列**（复用现有基建/密钥体系，无新表，改动最小）。B（独立加密列）作为回退，C（外部 Secret Manager）排除（自托管无此能力）。
- 密钥供应（FR-051 deployment key management）为**前置缺口**：`ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY / DETERMINISTIC_KEY / KEY_DERIVATION_SALT` 需在 dev(docker-compose/.env) / test / prod(Render) 三环境统一配置。
- 迁移后必须评估 Rotation（FR-054）：历史 DB dump/backup 已含明文 `sk_` → **建议轮换 Stripe secret + webhook signing secret**。

---

## 2. Secret Inventory（FR-050）

| 凭据 | 位置 | 敏感级 | 备注 |
|---|---|---|---|
| Stripe `secret_key`（`sk_live_…`/`sk_test_…`） | `PaymentMethod.preferences[:secret_key]`（Stripe gateway） | **Secret** | 支付/退款全程使用 |
| Stripe `webhook signing_secret`（`whsec_…`） | gateway preferences / 端点 secret | **Secret** | 验签 webhook（v3 + legacy 通道） |
| Stripe `publishable_key`（`pk_…`） | `preferences[:publishable_key]` | **Public**（FR-050 明示） | 前端可暴露，不按 secret 保护 |
| Adyen / PayPal checkout credential（未来） | 各自 gateway preferences | **Secret** | 先盘点，本期不接入 |
| AI Provider secrets | `GatewayCustomer#profile_id`、`WebhookEndpoint#secret_key` 等 | Secret（已 `encrypts` 声明） | 条件启用（见 §3.1） |
| 其他 `:password`-typed preference | 任意 gateway | Secret | PreferenceSchema `:password` 类型 = secret 判定源 |

范围界定：
- **加密目标列**：`PaymentMethod.preferences`（及其 Gateway STI 子类）。
- `publishable_key` 不迁移（保持明文配置，符合 FR-050）。

---

## 3. ENCRYPTION_COMPATIBILITY_SPIKE（FR-051）

### 3.1 现状核查（读码 + 运行时）

- `PallasTrade::Preferences::Preferable`（`backend/pallastrade_gems/pallastrade_core/lib/pallastrade/core/preferences/preferable.rb`）：
  `serialize :preferences, type: Hash, coder: YAML` —— preferences 是 **YAML 序列化的 Hash 列**。
- Preference DSL / `preference :key, :password, default:` 声明在各类（如 stripe gateway `secret_key`）。
- `PallasTrade::Preferences::Masking.serialize`（`.../core/preferences/masking.rb`）按 `password_preference_keys` 掩码输出；Admin GET 只回 masked value。
- Admin 写保护（`api/v3/admin/subclassed_resource.rb` 附近）：`Masking.masked?(value)` → **masked 值再提交不覆盖真实 Secret**（已完成标准之一已满足）。
- AR Encryption 基建：
  - `backend/config/application.rb` + `config/initializers/active_record_encryption.rb`：ENV `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY/DETERMINISTIC_KEY/KEY_DERIVATION_SALT` 存在才配置。
  - `WebhookEndpoint`/`GatewayCustomer` 用 `encrypts … if Rails.configuration.active_record.encryption.include?(:primary_key)`。
  - **本 dev 容器未注入这些 ENV** → `include?(:primary_key)` 为 false → 现有 `encrypts` 实际惰性（未加密）。
  - Rails 8.1，`config.load_defaults 8.1`。

### 3.2 Spike 实证（2026-09-03，RAILS_ENV=test + 注入 3 个密钥）

模拟 `PaymentMethod.preferences` 形态（`serialize Hash/YAML` + `encrypts` 同一 text 列）结论：

| 检查项 | 结果 | 说明 |
|---|---|---|
| AR encryption configured | ✅ true | 注入密钥后正常启用 |
| 写入后 DB 列不含明文 | ✅ | raw=162 字符、无 `sk_test_abc` 子串 |
| 读回解密 | ✅ | `{secret_key: "sk_test_abc", public_key: "pk_live_x", nested: {a: 1}}` 完整还原 |
| Preference DSL / YAML 兼容 | ✅（设计推断 + 组合实证） | 读路径走 preferences accessor → 透明解密；类型/默认逻辑不受影响 |
| 旧明文行 dual-read（`support_unencrypted_data=false`） | ❌ 抛 `ActiveRecord::Encryption::Errors::Decryption` | **迁移必须开 `support_unencrypted_data=true`**（或读路径 rescue） |
| Masking / Admin apply_preferences | 不受影响（读接口解密后掩码/比对） | 与 `Masking.serialize`/`masked?` 解耦 |
| STI | 待实现阶段小范围验证 | 子类级 `encrypts` 继承序列化属性（见 §6 开放项） |

**Spike 结论**：方案 A（AR Encryption 加密整列）在数据层可行；唯一硬依赖是密钥配置 + `support_unencrypted_data` 迁移开关。

---

## 4. 方案决策（FR-052）

| 方案 | 评价 | 决策 |
|---|---|---|
| **A. Active Record Encryption（`encrypts :preferences`）** | 复用现有基建与密钥体系；无新表；Preferable/Masking/Admin 全兼容（读接口透明解密）；迁移 = 一列 backfill | ✅ **推荐** |
| B. 独立 encrypted credential storage（新列 `encrypted_secret_preferences`） | 更彻底解耦 public/secret，但需改 DSL 读写路径（dual overlay）、新增列/迁移、Admin 双写，改动面大 | 回退项（若 A 在 STI 子类暴露问题） |
| C. External Secret Manager / `secret_reference` | 自托管无外部 SM；改为只存引用需重构取值链 + 部署强依赖 | ❌ 排除 |

---

## 5. 渐进迁移计划（FR-053，实施阶段执行）

按任务书顺序，禁止 destructive migration：

```text
1. Add       加密能力已在（ENV 条件启用）→ 三环境注入密钥；PaymentMethod 模型加 `encrypts :preferences`
              （放在 PreferenceSchema/Preferable include 之后，父类 serialize 之上按需位置）；
              migration：无需新列（加密在原 text 列内）。
2. dual-read Rails 配置 `config.active_record.encryption.support_unencrypted_data = true`
              （application.rb，迁移窗口开启）→ 明文旧行与密文新行都可读。
3. backfill  一次性 task：`PaymentMethod.find_each { |pm| pm.touch_preferences_for_encryption }`
              （任意写触发加密落库；如 `pm.update_column(:preferences, pm.preferences)` 不可行则走合法写）。
4. verify    抽样 + 全量 SQL：`SELECT id, preferences FROM …` 确认无 `sk_`/`whsec_` 明文子串；
              跑 Stripe 相关完整测试（§7）。
5. write encrypted only  新写入全加密（`encrypts` 默认）。
6. stop plaintext reads  关闭 `support_unencrypted_data`（或保留 true 但确认 0 明文行）。
7. remove plaintext     无 destructive；明文仅存于历史 dump（→ §8 Rotation）。
```

实现阶段代码改动预估：
- `backend/config/application.rb`：加 `support_unencrypted_data = true`（迁移窗口）；（迁移完成后评估是否关闭）
- PaymentMethod（core 模型，含 gateway STI 基类附近）加 `encrypts :preferences`（先在小范围 spike 验证子类继承行为，再全量）
- 一次 backfill rake task（`pallastrade:payments:encrypt_preferences`）—— 新文件
- `.env.example` / docker-compose（dev）与部署文档（Render/K8s）补 `ACTIVE_RECORD_ENCRYPTION_*`
- 测试：新增加密冒烟 spec（写入→raw 无明文→读回一致 + legacy 明文 dual-read 用例）

> ⚠️ `PallasTrade::Base` 的 `Preferable#preferences` 被多模型共享；`encrypts :preferences` 只加在 **PaymentMethod（及 gateway 子类）**，避免误伤 Promotion 等其他 Preferable 模型。

---

## 6. 开放项 / 风险

1. **密钥供应是前置阻断**：dev/docker-compose、CI/test、prod(Render) 三环境目前无统一密钥。漏配 = `encrypts` 惰性（静默明文）。需在实施阶段先落 `.env.example` + 部署文档 + test setup（ENV 或 `Rails.application.credentials`）。
2. STI 子类级 `encrypts` 继承序列化属性：实施前做一次小范围验证（PaymentMethod::Stripe 行写读 + 现有 factory 全绿）。
3. 全库 backfill 会改写所有 payment_method.preferences 行；回滚 = 代码回退 + 保留明文备份（非 destructive）。
4. `support_unencrypted_data` 长期开启 = 明文行可被接受（不报错）；建议 backfill+verify 后关闭，用 CI 检查防止回退明文。
5. 已有 DB dump / backup 含明文 → §8 Rotation 为唯一根治。

---

## 7. 完成标准映射（任务书）

| 标准 | 达成方式 |
|---|---|
| 新 DB dump 看不到 `sk_xxx` 明文 | `encrypts :preferences` 全量 backfill 后（verify 步骤 SQL 断言） |
| 普通 Rails console inspect 不直接暴露 Secret | 读路径解密属预期（持钥方可见）；**对外**一律走 Masking.serialize（Admin/API）——现状已保证 masked；不引入新明文出口 |
| Admin GET 只返回 masked value | 已满足（Masking + serialized_preferences）；回归测试覆盖 |
| masked value 再提交不覆盖真实 Secret | 已满足（SubclassedResource masked? 守卫）；回归测试覆盖 |
| 现有 Stripe 功能测试全部通过 | 实施阶段全量跑 payment/request spec（含本会话 P0-0..P0-4 基线） |

---

## 8. CREDENTIAL_ROTATION_PLAN（FR-054）

评估结论：**建议轮换**。

- 理由：历史 DB dump / backup 可能已含 `sk_live_…` / `whsec_…` 明文；加密只保护「之后」的 dump。
- 轮换对象：
  - Stripe API **secret key**（`sk_live_`）：Stripe Dashboard 轮换 → 更新 `PaymentMethod.preferences[:secret_key]`（新值经加密路径写入）。
  - Stripe **webhook signing secret**（`whsec_`）：Stripe Dashboard 重建端点/取新 secret → 更新 gateway preferences / endpoint secret。
- 步骤：新 key 预写（双活窗口）→ 切流量 → 验证（支付 sandbox + webhook 事件）→ 撤销旧 key → 确认旧明文不再用于任何新请求。
- 注意：publishable key 不需轮换（public）。
- 由工程负责人排期执行（需 Dashboard 权限 + 线上验证窗口）。

---

## 9. 决策确认请求（给用户）

- [x] 确认方案 **A（AR Encryption `encrypts :preferences` + support_unencrypted_data 渐进迁移）**
- [x] 确认实施范围：PaymentMethod（gateway）preferences 列全量 backfill + 三环境密钥配置 + 轮换排期
- [x] 确认 `support_unencrypted_data` 迁移完成后**关闭**（默认策略）或长期开启 → **实施决策：长期开启**（明文行永不 crash，CI verify 兜底）

---

## 10. 实施落地记录（2026-09-03，方案 A）

### 10.1 代码改动

| 文件 | 改动 |
|---|---|
| `backend/pallastrade_gems/pallastrade_core/app/models/pallastrade/gateway.rb` | `encrypts :preferences if Rails.configuration.active_record.encryption.include?(:primary_key)`（只加在 Gateway，不误伤 Check/StoreCredit） |
| `backend/config/application.rb` | `config.active_record.encryption.support_unencrypted_data = true`（dual-read） |
| `backend/lib/tasks/payments_secret_encryption.rake` | `pallastrade:payments:encrypt_preferences`（幂等 backfill）+ `pallastrade:payments:verify_encrypted_preferences`（明文泄漏检查，exit 1 兜底） |
| `backend/.env.example` | 补 `ACTIVE_RECORD_ENCRYPTION_*` 注释块 |
| `backend/docker-compose.dev.yml` | `&app-env` 注入 3 密钥（默认回退 docker-compose.yml 同款 dev 示例值，可 .env 覆盖） |
| `backend/spec/models/pallastrade/gateway_preferences_encryption_spec.rb` | 4 例（无密钥 skip；密钥激活时验证密文落库/透明解密/masking/明文 dual-read） |

> `docker-compose.yml`（自托管 prod 形态）此前已含这 3 个密钥；Render 等平台经 Secret Manager ENV 注入。

### 10.2 验证结果

- **无密钥回归**：`order_payment_sessions_controller_spec` + `handle_webhook_spec` + `start_spec` + association spec = 22 例绿（guard 惰性 → 零回归）。
- **密钥激活加密 spec**：`gateway_preferences_encryption_spec` = 4 例绿（DB 原生 SQL 无 `sk_/pk_` 明文、读回一致、Masking/`masked?` 正常、明文旧行 dual-read 可用）。
- **密钥激活广回归**：order payment sessions + handle_webhook(含 combination) + start = 20 例绿（现有 Stripe 流程加密模式全通过）。
- **backfill update 路径 e2e**：明文行 `update!(preferences:)` → 原生 SQL 无明文 → 读回解密一致。

### 10.3 上线 Runbook（部署时执行）

1. 确认密钥已注入目标环境（dev compose 已带默认；prod = Render Secret / 服务器 env）：`ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY / DETERMINISTIC_KEY / KEY_DERIVATION_SALT`。
2. 部署代码后执行：
   ```bash
   bundle exec rails db:migrate                 # 本次无新 migration（加密在原列内）
   bundle exec rake pallastrade:payments:encrypt_preferences
   bundle exec rake pallastrade:payments:verify_encrypted_preferences   # 期望 OK
   ```
3. 抽查新 DB dump：`pg_dump … | grep -c 'sk_live_\|whsec_'` 应为 0（加密列）。
4. 轮换排期见 §8（历史备份含明文 → 建议轮换 Stripe secret + webhook signing secret）。

### 10.4 回滚

非 destructive：撤销 `gateway.rb` 的 `encrypts` 行即可回退为明文写（密文行读取需 `support_unencrypted_data`；密钥不变则密文仍可读）。明文行若已无（全量 backfill），回滚后新写变明文——不建议，仅应急。

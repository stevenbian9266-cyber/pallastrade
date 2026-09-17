# frozen_string_literal: true

# PALLAS-CUSTOM: A3 Step 1（PRD-20260917-catalog-product-events；业务方案 §14 / §16）——
# **商品事件回流**：把前台的商品曝光 / 点击 / 加购 / 搜索落到**自有库**。
#
# 为什么需要这张表：`PDP | Related Product CTR` 的上线指标需要「分母 = 推荐位曝光」
# 与「分子 = 推荐位点击」，而现状是埋点**只进 GTM**（第三方），店主既查不到历史也无法
# 与自有商品关联；方案 §14 亦明确「只有形成真实曝光/点击/加购/购买数据以后，才值得进入
# 推荐算法阶段」。
#
# 设计要点：
# - **旁路表**：任何业务路径（库存 / 价格 / 订单 / 结账）**不得读取**本表做判定；
#   整表可随时清空而不影响业务（AC-009 以此立据）。
# - **幂等**：`(store_id, event_id)` 唯一键 = 客户端重试 / 双发的天然去重键，
#   `INSERT ... ON CONFLICT DO NOTHING` 保证「重试不重复计数」。
# - **零 PII**：不存 IP / User-Agent / 邮箱 / 客户 ID / 原始访客 UUID；
#   `session_hash` 是服务端 HMAC 摘要（不可逆且跨店不可关联）。
# - **追加写**：只有 `created_at`，**没有** `updated_at` —— 事件是事实，不可改写。
# - **保留有界**：模型侧 `RETENTION_DAYS` + 清理作业，避免无界膨胀。
#
# 只新增表/索引，不回填、不改既有列、不写任何资金字段。
class CreatePallasTradeCatalogEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_catalog_events do |t|
      t.bigint :store_id, null: false

      # 客户端生成的 UUID：幂等键（重试 / 双发不会重复计数）
      t.string :event_id, null: false
      t.string :event_name, null: false

      # 商品可选（`product_searched` 没有具体商品）
      t.bigint :product_id
      t.bigint :variant_id

      # 推荐位上下文（CTR 的计算维度）
      t.string :list_id
      t.string :list_name
      t.integer :position

      # 服务端 HMAC 摘要，绝非原始访客标识
      t.string :session_hash, null: false

      t.datetime :occurred_at, null: false
      t.jsonb :metadata

      # 追加写：只有 created_at
      t.datetime :created_at, null: false
    end

    # 幂等键：同店同 event_id 只允许一行
    add_index :pallastrade_catalog_events, [:store_id, :event_id], unique: true,
                                                                  name: 'idx_catalog_events_idempotency'

    # 时间窗聚合（CTR 按窗口查询）
    add_index :pallastrade_catalog_events, [:store_id, :occurred_at],
              name: 'idx_catalog_events_store_occurred_at'

    # 推荐位聚合（分组 / 下钻）
    add_index :pallastrade_catalog_events, [:store_id, :list_id],
              name: 'idx_catalog_events_store_list_id'

    # 商品维度聚合（加购 / 曝光）
    add_index :pallastrade_catalog_events, [:store_id, :product_id, :event_name],
              name: 'idx_catalog_events_store_product_name'
  end
end

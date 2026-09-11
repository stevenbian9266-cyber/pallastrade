# frozen_string_literal: true

# PALLAS-CUSTOM: 权限注册表（2026-08-16 权限体系重构）
# 注册后台「功能权限 / 数据权限」矩阵可配置的资源：可用操作 + 可数据过滤字段。
# UI 渲染权限矩阵、Ability 判定、nav:validate 校验都读此注册表。
# 新增可授权资源时在此登记（resource → model_class + actions + data_fields）。

Rails.application.config.after_initialize do
  reg = PallasTrade::PermissionRegistry

  reg.register(:orders,
               model_class: PallasTrade::Order,
               actions: %w[read create update destroy export],
               data_fields: %w[user_id store_id channel_id])
  reg.register(:products,
               model_class: PallasTrade::Product,
               actions: %w[read create update destroy export],
               data_fields: %w[store_id])
  # PRD-20260911-promo-batch5b 盘点发现（D6）：用户表无 store_id 列，原声明的
  # data_fields: store_id 无法执行（数据范围选「按店」时会让 accessible_by 生成
  # users.store_id 条件而报错）→ 改为空声明；矩阵数据范围选项不受影响。（能力/行为不变）
  reg.register(:customers,
               model_class: PallasTrade.user_class,
               actions: %w[read create update destroy export],
               data_fields: [])
  # PRD-20260911-promo-batch5b: 一个 capability 覆盖多个模型——后台促销管理
  # 同时含 Promotion（列表/编辑）、PromotionRule（规则弹窗）、PromotionAction（动作弹窗），
  # 三者在后台各自 `authorize!`，所以 DB 角色拿到 promotions.* 必须对三个模型都生效。
  reg.register(:promotions,
               model_class: PallasTrade::Promotion,
               models: [PallasTrade::Promotion, PallasTrade::PromotionRule, PallasTrade::PromotionAction],
               actions: %w[read create update destroy],
               data_fields: %w[store_id])
  # PRD-20260911-promo-batch5b: 券码后台（promotion 嵌套的 Coupon Codes 只读列表）
  # 单独成资源；CouponCode 无 store_id 列，数据范围经 belongs_to :promotion 上卷。
  reg.register(:coupon_codes,
               model_class: PallasTrade::CouponCode,
               actions: %w[read create update destroy],
               data_fields: %w[store_id])
  reg.register(:returns,
               model_class: PallasTrade::CustomerReturn,
               actions: %w[read create update destroy],
               data_fields: %w[store_id])
  reg.register(:reports,
               model_class: nil,
               actions: %w[read export],
               data_fields: [])
  reg.register(:posts,
               model_class: PallasTrade::Post,
               actions: %w[read create update destroy],
               data_fields: %w[store_id])
  reg.register(:emails,
               model_class: nil,
               actions: %w[read update],
               data_fields: [])
  reg.register(:abandoned_cart_notifications,
               model_class: PallasTrade::AbandonedCartNotification,
               actions: %w[read update destroy],
               data_fields: %w[store_id])
  reg.register(:reviews,
               model_class: PallasTrade::Review,
               actions: %w[read update destroy],
               data_fields: %w[store_id])
  # TXN-P2-7 slice2: durable CommerceTransaction 运维查看/恢复（Admin Transactions）
  reg.register(:transactions,
               model_class: PallasTrade::CommerceTransaction,
               actions: %w[read update],
               data_fields: %w[store_id])
  # PRD-20260910-promo-batch3c: 核销台账只读（Admin API + Promotions → Redemptions）
  reg.register(:promotion_redemptions,
               model_class: PallasTrade::PromotionRedemption,
               actions: %w[read],
               data_fields: %w[store_id])
  # PRD-20260911-promo-batch6 (PR-P9-2, D2=A): 促销分类后台 CRUD。
  # PromotionCategory 无 store_id 列（安装级共享分类）→ 数据范围为空声明。
  reg.register(:promotion_categories,
               model_class: PallasTrade::PromotionCategory,
               actions: %w[read create update destroy],
               data_fields: [])
  reg.register(:developers,
               model_class: nil,
               actions: %w[read create update destroy],
               data_fields: [])
end

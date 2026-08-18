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
  reg.register(:customers,
               model_class: PallasTrade.user_class,
               actions: %w[read create update destroy export],
               data_fields: %w[store_id])
  reg.register(:promotions,
               model_class: PallasTrade::Promotion,
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
  reg.register(:developers,
               model_class: nil,
               actions: %w[read create update destroy],
               data_fields: [])
end

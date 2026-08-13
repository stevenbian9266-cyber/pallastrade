# frozen_string_literal: true

# # PRD-20260813-admin-移除管理后台-integrations-菜单及相关逻辑
# # AI 模块解耦：创建独立 pallastrade_ai_providers 表，迁移 AI provider 记录，
# # 关联表外键重指向新表，随后 drop 旧 pallastrade_integrations 表。
# 注意：类名必须用 AI 大写以匹配 engine 的 inflect.acronym('AI') 的 camelize 推断。
class CreatePallasTradeAIProviders < ActiveRecord::Migration[8.1]
  LEGACY_TYPES = %w[
    PallasTrade::AI::Integrations::DeepSeek
    PallasTrade::AI::Integrations::OpenAI
  ].freeze

  NEW_TYPES = %w[
    PallasTrade::AI::Provider::DeepSeek
    PallasTrade::AI::Provider::OpenAI
  ].freeze

  def up
    create_table :pallastrade_ai_providers do |t|
      t.references :store, null: false, index: true
      t.string :type, null: false, index: true
      t.text :preferences
      t.boolean :active, default: false, null: false, index: true
      t.timestamps
    end

    migrate_provider_records if table_exists?(:pallastrade_integrations)

    # provider_secrets: integration_id → provider_id（关联数据为 0 条，零风险）
    # 注意：rename_column 会自动重命名依赖该列的索引（on_integration_id → on_provider_id），
    # 无需（也不能）再显式 rename_index，否则会因旧索引名不存在而报 PG::UndefinedTable。
    if table_exists?(:pallastrade_ai_provider_secrets)
      remove_foreign_key :pallastrade_ai_provider_secrets, column: :integration_id, to_table: :pallastrade_integrations
      rename_column :pallastrade_ai_provider_secrets, :integration_id, :provider_id
      add_foreign_key :pallastrade_ai_provider_secrets, :pallastrade_ai_providers, column: :provider_id
    end

    # ai_models.provider_id / ai_runs.provider_id：外键重指向新表（数据 0 条）
    if foreign_key_exists?(:pallastrade_ai_models, :pallastrade_integrations, column: :provider_id)
      remove_foreign_key :pallastrade_ai_models, column: :provider_id, to_table: :pallastrade_integrations
      add_foreign_key :pallastrade_ai_models, :pallastrade_ai_providers, column: :provider_id
    end

    # 旧 integrations 表已无引用，drop
    drop_table :pallastrade_integrations, if_exists: true
  end

  def down
    create_table :pallastrade_integrations do |t|
      t.references :store, null: false, index: true
      t.string :type, null: false, index: true
      t.text :preferences
      t.boolean :active, default: false, null: false, index: true
      t.timestamps
    end

    if table_exists?(:pallastrade_ai_providers)
      execute(<<~SQL)
        INSERT INTO pallastrade_integrations (store_id, type, preferences, active, created_at, updated_at)
        SELECT store_id,
               CASE type
                 WHEN 'PallasTrade::AI::Provider::DeepSeek' THEN 'PallasTrade::AI::Integrations::DeepSeek'
                 WHEN 'PallasTrade::AI::Provider::OpenAI' THEN 'PallasTrade::AI::Integrations::OpenAI'
               END,
               preferences, active, created_at, updated_at
        FROM pallastrade_ai_providers
      SQL
    end

    # 外键回移
    if table_exists?(:pallastrade_ai_provider_secrets)
      remove_foreign_key :pallastrade_ai_provider_secrets, column: :provider_id, to_table: :pallastrade_ai_providers
      rename_column :pallastrade_ai_provider_secrets, :provider_id, :integration_id
      add_foreign_key :pallastrade_ai_provider_secrets, :pallastrade_integrations, column: :integration_id
    end

    if foreign_key_exists?(:pallastrade_ai_models, :pallastrade_ai_providers, column: :provider_id)
      remove_foreign_key :pallastrade_ai_models, column: :provider_id, to_table: :pallastrade_ai_providers
      add_foreign_key :pallastrade_ai_models, :pallastrade_integrations, column: :provider_id
    end

    drop_table :pallastrade_ai_providers, if_exists: true
  end

  private

  def migrate_provider_records
    execute(<<~SQL)
      INSERT INTO pallastrade_ai_providers (store_id, type, preferences, active, created_at, updated_at)
      SELECT store_id,
             CASE type
               WHEN 'PallasTrade::AI::Integrations::DeepSeek' THEN 'PallasTrade::AI::Provider::DeepSeek'
               WHEN 'PallasTrade::AI::Integrations::OpenAI' THEN 'PallasTrade::AI::Provider::OpenAI'
             END,
             preferences, active, created_at, updated_at
      FROM pallastrade_integrations
      WHERE type IN ('PallasTrade::AI::Integrations::DeepSeek', 'PallasTrade::AI::Integrations::OpenAI')
    SQL
  end
end

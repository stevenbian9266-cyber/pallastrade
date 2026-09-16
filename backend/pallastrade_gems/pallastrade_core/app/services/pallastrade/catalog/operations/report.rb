# frozen_string_literal: true

module PallasTrade
  module Catalog
    module Operations
      # 商品运营报表（PRD-20260916-catalog-operations-report；商品域审计 G-6）—— **只读聚合**：
      #
      #   * 数据源：`pallastrade_audit_logs` —— D-1 的 `ProductHistory::Recorder` 已经把每次
      #     商品写入记进这里（`product.created` / `product.updated` / `product.bulk_price_updated`…），
      #     本报表只是把它读成两个可决策的数字，**零新表、零写入**；
      #   * 批量 vs 单条：`record_bulk` 给每个受影响商品各写一条并带 `metadata['source'] = 'bulk'`；
      #     批次本身没有 id，所以这里给出两个诚实数字 —— **条目数**（操作规模）与**覆盖商品数**（去重）；
      #   * 维护比率：窗口内 `product.updated` 条目数 ÷ 窗口内被动过的不同商品数（分母 0 → 0）；
      #   * 操作者榜：`actor_label`，无 actor 的写入归入 `system`（不得算成"人"的动作）。
      #
      # 铁律：**零写库**；三个聚合都在数据库完成（查询数与窗口内行数无关）。
      #
      # ⚠️ **口径**：`pallastrade_audit_logs` 没有 store 维度 → 本报表是**全库口径**，返回
      # `scope_note: 'all_stores'`，页面必须如实标注。多店作用域是审计 G-8 的独立议题，本批不扩范围。
      class Report
        prepend PallasTrade::ServiceModule::Base

        RESOURCE_TYPE = 'PallasTrade::Product'
        DEFAULT_WINDOW_DAYS = 7
        ALLOWED_WINDOW_DAYS = [7, 30].freeze
        BULK_SOURCE = 'bulk'
        UPDATE_ACTION = 'product.updated'
        SYSTEM_ACTOR = 'system'
        SCOPE_NOTE = 'all_stores'

        # @param window_days [Integer, String] 7 or 30 (anything else falls back to 7)
        # @param now [Time]
        # @return [PallasTrade::ServiceModule::Result] success(Hash)
        def call(window_days: DEFAULT_WINDOW_DAYS, now: Time.current)
          days = normalize_window(window_days)
          since = now - days.days
          scoped = entries_since(since)

          success({
                    window_days: days,
                    since: since,
                    totals: totals_for(scoped),
                    operations: split_by_source(scoped),
                    maintenance: maintenance_for(scoped),
                    actors: actor_rows(scoped),
                    scope_note: SCOPE_NOTE
                  })
        end

        private

        def normalize_window(value)
          days = value.to_i
          ALLOWED_WINDOW_DAYS.include?(days) ? days : DEFAULT_WINDOW_DAYS
        end

        # Every product audit entry inside the window. Kept as a relation so every
        # aggregate below runs in the database.
        def entries_since(since)
          PallasTrade::AuditLog.
            where(resource_type: RESOURCE_TYPE).
            where(arel_table[:occurred_at].gteq(since))
        end

        def arel_table
          PallasTrade::AuditLog.arel_table
        end

        def totals_for(scoped)
          {
            entries: scoped.count,
            products_touched: scoped.distinct.count(:resource_id)
          }
        end

        # Bulk operations were never a first-class record (the recorder writes one
        # row per affected product carrying `source: 'bulk'`), so "bulk" is decided
        # **per entry** from its metadata — never per action name, because the same
        # action can arrive from a single edit or from a bulk run.
        def split_by_source(scoped)
          {
            bulk: aggregate(bulk_scope(scoped)),
            single: aggregate(single_scope(scoped))
          }
        end

        def bulk_scope(scoped)
          scoped.where("metadata ->> 'source' = ?", BULK_SOURCE)
        end

        def single_scope(scoped)
          scoped.where("metadata ->> 'source' IS DISTINCT FROM ?", BULK_SOURCE)
        end

        # One aggregate per scope: entry count, covered-product count, and the
        # per-action breakdown. All three run in the database.
        def aggregate(scope)
          rows = scope.
                 group(:action).
                 pluck(
                   Arel.sql('action'),
                   Arel.sql('COUNT(*)'),
                   Arel.sql('COUNT(DISTINCT resource_id)')
                 ).
                 map { |action, entries, products| { action: action.to_s, entries: entries, products: products } }

          {
            entries: rows.sum { |row| row[:entries] },
            products: scope.distinct.count(:resource_id),
            actions: rows.sort_by { |row| -row[:entries] }
          }
        end

        # Average maintenance operations per touched product (0 when nothing moved).
        def maintenance_for(scoped)
          updates = scoped.where(action: UPDATE_ACTION)
          update_entries = updates.count
          touched = scoped.distinct.count(:resource_id)

          {
            update_entries: update_entries,
            products_touched: touched,
            per_product: touched.positive? ? (update_entries.to_f / touched).round(2) : 0.0
          }
        end

        def actor_rows(scoped)
          scoped.
            group(:actor_label).
            count.
            map { |label, count| { actor: label.presence || SYSTEM_ACTOR, entries: count } }.
            sort_by { |row| -row[:entries] }
        end
      end
    end
  end
end

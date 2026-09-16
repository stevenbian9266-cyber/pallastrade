# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片4（PRD-20260916-payments-d13d-fx-snapshot；业务方案 §70.4）——
# `Currencies::Rates::Upsert` —— 汇率行的**唯一写入口**（手工录入 / provider / 第三方批量）：
#   * 幂等：按 `identity_key`（店/全局 + 币种对 + 来源 + 生效起点）upsert，重复提交只更新原行；
#   * 撤销：`status='revoked'`（**保留历史行**，历史快照可复算）；
#   * 审计：`currency_rate_changed`（含 before/after）/ `currency_rate_revoked`。
#
# 铁律：只写汇率表 + 审计；不改订单/支付金额、不写资金流水、不调外部 API。
module PallasTrade
  module Currencies
    module Rates
      class Upsert
        prepend PallasTrade::ServiceModule::Base

        # @param store [PallasTrade::Store, nil] nil = 全局汇率
        # @return [PallasTrade::ServiceModule::Result] success({ rate:, created: })
        def call(base_currency:, quote_currency:, rate:, source: 'manual', priority: nil,
                 effective_from: nil, effective_until: nil, store: nil, note: nil, actor: nil,
                 revoke: false, metadata: {})
          row = find_row(
            base_currency: base_currency, quote_currency: quote_currency, source: source,
            effective_from: effective_from, store: store
          )
          created = row.new_record?
          before = snapshot(row) unless created

          if revoke
            row.save! if created
            row.revoke!(actor: actor)
            record_audit('currency_rate_revoked', row, before: before, after: snapshot(row), actor: actor)
            return success({ rate: row, created: created })
          end

          row.assign_attributes(
            rate: rate,
            priority: priority.nil? ? PallasTrade::CurrencyRate.default_priority_for(source) : priority,
            effective_until: effective_until,
            note: note,
            metadata: (row.metadata || {}).merge(metadata || {})
          )
          row.created_by_id ||= actor_id(actor)

          row.save!
          record_audit('currency_rate_changed', row, before: before, after: snapshot(row), actor: actor)
          success({ rate: row, created: created })
        rescue ActiveRecord::RecordInvalid => e
          failure(nil, e.record.errors.full_messages.join(', '))
        end

        private

        def find_row(base_currency:, quote_currency:, source:, effective_from:, store:)
          key = PallasTrade::CurrencyRate.identity_key_for(
            base_currency: base_currency, quote_currency: quote_currency, source: source,
            effective_from: effective_from, store: store
          )
          row = PallasTrade::CurrencyRate.find_or_initialize_by(identity_key: key)
          row.assign_attributes(
            base_currency: base_currency, quote_currency: quote_currency, source: source,
            effective_from: effective_from, store_id: store&.id
          )
          row
        end

        def snapshot(row)
          return nil if row.new_record?

          {
            base_currency: row.base_currency,
            quote_currency: row.quote_currency,
            rate: row.rate.to_s,
            source: row.source,
            priority: row.priority,
            status: row.status,
            effective_from: row.effective_from&.iso8601,
            effective_until: row.effective_until&.iso8601,
            note: row.note
          }
        end

        def actor_id(actor)
          case actor
          when Hash then actor[:id]
          when nil then nil
          else (actor.respond_to?(:id) ? actor.id : nil)
          end
        end

        def record_audit(action, row, before:, after:, actor:)
          PallasTrade::Audit.record(
            action: action, actor: actor, resource: row, before: before, after: after
          )
        end
      end
    end
  end
end

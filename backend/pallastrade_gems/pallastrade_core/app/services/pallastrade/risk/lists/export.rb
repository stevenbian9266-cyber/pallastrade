# frozen_string_literal: true

require 'csv'

# PALLAS-CUSTOM: D15 切片1（PRD-20260916-payments-d15-risk-lists；业务方案 §72.3 导出）——
# `Risk::Lists::Export` —— 名单导出（CSV），列与导入**同构**（导出→再导入 = 往返一致）。
#
# 语义：
#   * 筛选口径与后台工作台**同源**（`PaymentRiskList.filter_by`）→ 页面看到什么就导出什么；
#   * 导出**保留原值**（运营需要它去比对/交接），因此必须配合权限 + 审计；
#   * 审计只记计数与筛选条件（不落明细值）。
module PallasTrade
  module Risk
    module Lists
      class Export
        prepend PallasTrade::ServiceModule::Base

        HEADERS = %w[list_type subject_type value expires_at reason].freeze

        # @param store [PallasTrade::Store, nil]
        # @param list_type [String, nil]
        # @param subject_type [String, nil]
        # @param scope_filter [String, nil] all / active / expired / revoked
        # @param actor [Object, nil]
        # @return [PallasTrade::ServiceModule::Result] success({ csv:, count: })
        def call(store: nil, list_type: nil, subject_type: nil, scope_filter: nil, actor: nil)
          entries = PallasTrade::PaymentRiskList
                    .filter_by(store: store, list_type: list_type, subject_type: subject_type, scope_filter: scope_filter)
                    .recent_first
                    .to_a

          csv = ::CSV.generate(headers: true) do |out|
            out << HEADERS
            entries.each do |entry|
              out << [entry.list_type, entry.subject_type, entry.value, entry.expires_at&.iso8601, entry.reason]
            end
          end

          record_audit(store, entries.size, list_type, subject_type, scope_filter, actor)

          success({ csv: csv, count: entries.size })
        end

        private

        def record_audit(store, count, list_type, subject_type, scope_filter, actor)
          PallasTrade::Audit.record(
            action: 'risk_list_exported',
            actor: actor,
            resource: store,
            after: {
              count: count,
              list_type: list_type.presence,
              subject_type: subject_type.presence,
              scope_filter: scope_filter.presence || 'all'
            }
          )
        rescue StandardError => e
          Rails.logger.error("[Risk::Lists::Export] audit failed: #{e.class} #{e.message}")
        end
      end
    end
  end
end

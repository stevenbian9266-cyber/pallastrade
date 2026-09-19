# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Store
        module Orders
          # PRD-20260919-checkout：补付重验（payment preflight）只读报告序列化。
          #
          # 数据源 = `PallasTrade::OrderCheckout::Revalidate.call(order:, dry_run: true)`
          # 的报告（dry-run：不落库、不发事件、不建会话）；本类只做**形状收敛**
          # （固定键集 + 缺省 nil），不做任何领域计算/判定。
          class PaymentPreflightSerializer < PallasTrade::Api::V3::BaseSerializer
            typelize payable: :boolean,
                     order_id: :string,
                     number: [:string, { nullable: true }],
                     blockers: 'Array<{ code: string, message: string, ' \
                               'missing_requirements: string[], ' \
                               'items: Array<{ line_item_id: string, name: string }> }>',
                     changes: 'Array<{ kind: string, subject: string, ' \
                              'name: string | null, code: string | null, field: string | null, ' \
                              'line_item_id: string | null, variant_id: string | null, ' \
                              'before: string | null, after: string | null, ' \
                              'display_before: string | null, display_after: string | null, ' \
                              'amount: string | null, quantity: number | null, ' \
                              'reason: string | null }>',
                     invalid_items: 'Array<{ line_item_id: string, variant_id: string | null, ' \
                                    'name: string, sku: string | null, quantity: number, ' \
                                    'amount: string, reason: string }>',
                     quote: '{ checkout_version: number | null, price_version: string | null, ' \
                            'expires_at: string | null, amount_due: string | null, ' \
                            'display_amount_due: string | null, total: string | null, ' \
                            'display_total: string | null }',
                     amount_due_before: [:string, { nullable: true }],
                     amount_due_after: [:string, { nullable: true }],
                     display_amount_due_before: [:string, { nullable: true }],
                     display_amount_due_after: [:string, { nullable: true }],
                     total_before: [:string, { nullable: true }],
                     total_after: [:string, { nullable: true }],
                     display_total_before: [:string, { nullable: true }],
                     display_total_after: [:string, { nullable: true }],
                     window: '{ valid: boolean, expires_at: string | null, ' \
                             'window_minutes: number, reissued: boolean }'

            # 变更条目固定键集（缺省 nil）—— 契约稳定，前端按 kind 渲染
            CHANGE_KEYS = %w[
              kind subject name code field line_item_id variant_id
              before after display_before display_after amount quantity reason
            ].freeze

            normalize_changes = lambda do |report|
              Array(report['changes']).map do |change|
                CHANGE_KEYS.each_with_object({}) { |key, memo| memo[key] = change[key] }
              end
            end

            normalize_blockers = lambda do |report|
              Array(report['blockers']).map do |blocker|
                {
                  'code' => blocker['code'],
                  'message' => blocker['message'],
                  'missing_requirements' => Array(blocker['missing_requirements']),
                  'items' => Array(blocker['items']).map do |item|
                    { 'line_item_id' => item['line_item_id'], 'name' => item['name'] }
                  end
                }
              end
            end

            attribute(:id) { |report| report['order_id'] }
            attribute(:payable) { |report| report['payable'] }
            attribute(:order_id) { |report| report['order_id'] }
            attribute(:number) { |report| report['number'] }
            attribute(:blockers, &normalize_blockers)
            attribute(:changes, &normalize_changes)
            attribute(:invalid_items) { |report| Array(report['invalid_items']) }
            attribute(:quote) { |report| report['quote'] }
            attribute(:amount_due_before) { |report| report['amount_due_before'] }
            attribute(:amount_due_after) { |report| report['amount_due_after'] }
            attribute(:display_amount_due_before) { |report| report['display_amount_due_before'] }
            attribute(:display_amount_due_after) { |report| report['display_amount_due_after'] }
            attribute(:total_before) { |report| report['total_before'] }
            attribute(:total_after) { |report| report['total_after'] }
            attribute(:display_total_before) { |report| report['display_total_before'] }
            attribute(:display_total_after) { |report| report['display_total_after'] }
            attribute(:window) { |report| report['window'] }
          end
        end
      end
    end
  end
end

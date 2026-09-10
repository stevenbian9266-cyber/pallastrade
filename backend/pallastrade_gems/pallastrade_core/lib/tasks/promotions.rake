# frozen_string_literal: true

# PRD-20260909-promotions-promo-batch1 (AC-P3-2): ops-facing duplicate-code
# checker, to run BEFORE `db:migrate` on environments with existing data.
#
#   bundle exec rake pallastrade:promotions:check_duplicate_codes
#
# Prints every duplicate single-code group and whether each row has been used
# by an order. Raises when two USED promotions share a code, because the
# migration refuses to rename a used promotion automatically.
module PallasTrade
  module Tasks
    class PromoDuplicateCodeChecker
      def call
        groups = duplicate_groups
        if groups.empty?
          puts 'No duplicate single-code promotions found.'
          return
        end

        blocked = false
        groups.each do |store_id, normalized|
          ids = group_ids(store_id, normalized)
          used_ids = ids.select { |id| used_promotion?(id) }
          blocked = true if used_ids.size > 1

          puts "DUP store_id=#{store_id} code='#{normalized}' rows=#{ids.join(',')} used=#{used_ids.join(',') || '-'}"
        end

        if blocked
          raise 'Two or more USED promotions share a single code — resolve manually before migrating ' \
                '(see PRD-20260909-promo-batch1 AC-P3-2).'
        end

        puts 'Duplicates are safe to auto-resolve by the migration (only unused ones are renamed).'
      end

      private

      def duplicate_groups
        connection.execute(<<~SQL.squish).to_a.map { |r| [r['store_id'], r['normalized']] }
          SELECT store_id, lower(btrim(code)) AS normalized
            FROM pallastrade_promotions
           WHERE code IS NOT NULL
           GROUP BY store_id, lower(btrim(code))
          HAVING COUNT(*) > 1
        SQL
      end

      def group_ids(store_id, normalized)
        connection.execute(<<~SQL.squish).to_a.map { |r| r['id'] }
          SELECT id
            FROM pallastrade_promotions
           WHERE store_id = #{connection.quote(store_id)}
             AND lower(btrim(code)) = #{connection.quote(normalized)}
           ORDER BY id ASC
        SQL
      end

      def used_promotion?(id)
        connection.execute(<<~SQL.squish).to_a.any?
          SELECT 1
            FROM pallastrade_order_promotions
           WHERE promotion_id = #{connection.quote(id)}
           LIMIT 1
        SQL
      end

      def connection
        ActiveRecord::Base.connection
      end
    end

    # PRD-20260910-promotions-promo-batch3a (FR-013, D6)
    #
    # Idempotent backfill of the redemption ledger for historical data:
    #   pass 1 — every (order, promotion) with an eligible promotion adjustment
    #   pass 2 — every used coupon code attached to an order (covers orders whose
    #            adjustments were later removed/edited)
    # Rows are written as `committed` with historical timestamps; existing rows
    # (any state) are never overwritten. Dry run by default.
    class PromoRedemptionBackfill
      def initialize(dry_run: true)
        @dry_run = dry_run
      end

      def call
        created = 0
        skipped = 0

        candidates.each do |order_id, promotion_id|
          if existing?(order_id, promotion_id)
            skipped += 1
            next
          end

          created += 1
          create_redemption(order_id, promotion_id) unless @dry_run
        end

        puts "Backfill promotion redemptions: created=#{created} skipped=#{skipped} dry_run=#{@dry_run}"
      end

      private

      def candidates
        connection.execute(<<~SQL.squish).to_a.map { |row| [row['order_id'], row['promotion_id']] }
          SELECT DISTINCT a.order_id AS order_id, pa.promotion_id AS promotion_id
            FROM pallastrade_adjustments a
            JOIN pallastrade_promotion_actions pa ON pa.id = a.source_id
           WHERE a.source_type = 'PallasTrade::PromotionAction'
             AND a.eligible = true
          UNION
          SELECT DISTINCT cc.order_id AS order_id, cc.promotion_id AS promotion_id
            FROM pallastrade_coupon_codes cc
           WHERE cc.state = 1 AND cc.order_id IS NOT NULL AND cc.deleted_at IS NULL
        SQL
      end

      def existing?(order_id, promotion_id)
        PallasTrade::PromotionRedemption.exists?(order_id: order_id, promotion_id: promotion_id)
      end

      def create_redemption(order_id, promotion_id)
        order = PallasTrade::Order.find(order_id)
        promotion = PallasTrade::Promotion.find(promotion_id)
        timestamp = order.completed_at || order.created_at || Time.current

        PallasTrade::PromotionRedemption.create!(
          store_id: order.store_id || promotion.store_id,
          promotion: promotion,
          order: order,
          user_id: order.user_id,
          coupon_code: coupon_code_for(order, promotion),
          state: 'committed',
          amount: amount_for(order, promotion),
          currency: order.currency,
          reserved_at: timestamp,
          committed_at: timestamp
        )
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
        warn "skip backfill order=#{order_id} promotion=#{promotion_id}: #{e.class}"
      end

      def coupon_code_for(order, promotion)
        return nil unless promotion.multi_codes?

        promotion.coupon_codes.find_by(order_id: order.id)
      end

      def amount_for(order, promotion)
        order.all_adjustments.promotion.eligible.where(source_id: promotion.actions.select(:id)).sum(:amount)
      end

      def connection
        ActiveRecord::Base.connection
      end
    end
  end
end

namespace :pallastrade do
  namespace :promotions do
    desc 'Check duplicate single-code promotions (PRD-20260909-promo-batch1)'
    task check_duplicate_codes: :environment do
      PallasTrade::Tasks::PromoDuplicateCodeChecker.new.call
    end

    desc 'Backfill promotion redemptions ledger (PRD-20260910-promo-batch3a; dry run by default: pass "false" to apply)'
    task :backfill_redemptions, %i[dry_run] => :environment do |_task, args|
      dry_run = args[:dry_run].to_s.downcase != 'false'
      PallasTrade::Tasks::PromoRedemptionBackfill.new(dry_run: dry_run).call
    end
  end
end

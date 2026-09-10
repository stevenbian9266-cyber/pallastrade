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

    # PRD-20260910-promotions-promo-batch4a (FR-006): 存量订单成交快照回填。
    #   候选 = 已成交（completed_at 或标准流程 paid+）且当日有 eligible 促销调整的订单；
    #   逐单隔离 rescue；已冻结行跳过（幂等）；dry-run 默认，APPLY=1 才写库。
    class PromoOrderPromotionSnapshotBackfill
      def initialize(dry_run: true, store_id: nil, limit: nil)
        @dry_run = dry_run
        @store_id = store_id.presence
        @limit = limit.presence&.to_i
      end

      def call
        frozen = 0
        skipped = 0
        failed = 0

        candidate_ids.each do |order_id|
          order = PallasTrade::Order.find_by(id: order_id)
          next if order.nil?

          before = order.order_promotions.count(&:frozen?)
          rows = @dry_run ? preview(order) : PallasTrade::Promotions::Snapshot::Freeze.call(order)
          after = order.order_promotions.reload.count(&:frozen?)

          if after == before
            skipped += 1
          else
            frozen += (after - before)
          end

          print_row(order, rows) if @dry_run
        rescue StandardError => e
          failed += 1
          warn "skip backfill order=#{order_id}: #{e.class} #{e.message}"
        end

        puts "Backfill order promotion snapshots: candidates=#{candidate_ids.size} frozen=#{frozen} " \
             "skipped_orders=#{skipped} failed=#{failed} dry_run=#{@dry_run}"
      end

      private

      def candidates
        scope = PallasTrade::Order.where(
          "pallastrade_orders.completed_at IS NOT NULL OR pallastrade_orders.state IN (?)",
          PallasTrade::Promotions::Snapshot::Freeze::MONEY_CONFIRMED_STATES
        ).where(id: order_ids_with_promotion_adjustments)
        scope = scope.joins(:store).where(pallastrade_stores: { id: @store_id }) if @store_id
        scope = scope.limit(@limit) if @limit
        scope
      end

      def candidate_ids
        @candidate_ids ||= candidates.pluck(:id)
      end

      def order_ids_with_promotion_adjustments
        PallasTrade::Adjustment.
          where(source_type: 'PallasTrade::PromotionAction', eligible: true).
          where.not(order_id: nil).
          select(:order_id)
      end

      def preview(order)
        PallasTrade::Promotions::Projection::DiscountProjection.for(order: order).reject do |line|
          line.order_promotion&.frozen?
        end
      end

      def print_row(order, rows)
        rows.each do |row|
          promotion = row.respond_to?(:promotion) ? row.promotion : nil
          name = row.respond_to?(:name) ? row.name : promotion&.name
          code = row.respond_to?(:code) ? row.code : promotion&.code_for_order(order)
          amount = row.respond_to?(:amount) ? row.amount : 0
          puts [order.id, order.number, promotion&.id, name, code, amount, order.currency].join("\t")
        end
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

    desc 'Validate promotion rule/action definitions (PRD-20260910-promo-batch5a; STRICT=1 fails on errors)'
    task definitions: :environment do
      PallasTrade::Tasks::PromoDefinitionRegistryValidator.new(strict: ENV['STRICT'].to_s == '1').call
    end

    desc 'Backfill promotion redemptions ledger (PRD-20260910-promo-batch3a; dry run by default: pass "false" to apply)'
    task :backfill_redemptions, %i[dry_run] => :environment do |_task, args|
      dry_run = args[:dry_run].to_s.downcase != 'false'
      PallasTrade::Tasks::PromoRedemptionBackfill.new(dry_run: dry_run).call
    end

    desc 'Backfill order promotion snapshots (PRD-20260910-promo-batch4a; dry run by default, APPLY=1 to write)'
    task :backfill_order_promotion_snapshots, %i[store_id limit] => :environment do |_task, args|
      dry_run = ENV['APPLY'].to_s != '1'
      PallasTrade::Tasks::PromoOrderPromotionSnapshotBackfill.new(
        dry_run: dry_run,
        store_id: args[:store_id],
        limit: args[:limit]
      ).call
    end
  end
end

module PallasTrade
  module Tasks
    # PRD-20260910-promotions-promo-batch5a (PR-P7-3, AC-006)
    #
    # Consistency report for the promotion definition registry: every registered
    # rule/action must have a calculator bucket (when it computes amounts), an
    # admin form partial and — ideally — a locale label. Errors block; warnings
    # are informational. `STRICT=1` makes errors exit non-zero so CI/lefthook can
    # gate a PR that adds a definition without finishing the registration:
    #
    #   bundle exec rake pallastrade:promotions:definitions
    #   STRICT=1 bundle exec rake pallastrade:promotions:definitions
    class PromoDefinitionRegistryValidator
      def initialize(strict: false, registry: PallasTrade::Promotions::DefinitionRegistry)
        @strict = strict
        @registry = registry
      end

      def call
        issues = @registry.validate!
        print_report(issues)

        errors = issues.count { |issue| issue[:level] == :error }
        if errors.positive? && @strict
          raise "#{errors} promotion definition error(s) — see report above " \
                '(PRD-20260910-promotions-promo-batch5a AC-006)'
        end

        errors
      end

      private

      def print_report(issues)
        entries = @registry.entries
        rules = entries.count(&:rule?)
        actions = entries.count(&:action?)

        puts "Promotion definition registry: rules=#{rules} actions=#{actions} " \
             "errors=#{count(issues, :error)} warnings=#{count(issues, :warning)}"

        grouped = issues.group_by { |issue| issue[:kind] }
        [PallasTrade::Promotions::DefinitionRegistry::RULE,
         PallasTrade::Promotions::DefinitionRegistry::ACTION].each do |kind|
          kind_issues = grouped[kind] || []
          next if kind_issues.empty?

          puts "#{kind.to_s.upcase} issues:"
          kind_issues.each { |issue| puts "  [#{issue[:level]}] #{issue[:code]} #{issue[:key]}: #{issue[:message]}" }
        end

        puts 'Registry is consistent.' if issues.empty?
      end

      def count(issues, level)
        issues.count { |issue| issue[:level] == level }
      end
    end
  end
end

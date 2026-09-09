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
  end
end

namespace :pallastrade do
  namespace :promotions do
    desc 'Check duplicate single-code promotions (PRD-20260909-promo-batch1)'
    task check_duplicate_codes: :environment do
      PallasTrade::Tasks::PromoDuplicateCodeChecker.new.call
    end
  end
end

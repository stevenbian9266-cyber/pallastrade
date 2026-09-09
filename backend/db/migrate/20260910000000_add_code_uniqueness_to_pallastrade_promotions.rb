# frozen_string_literal: true

# PRD-20260909-promotions-promo-batch1 (AC-P3-1/AC-P3-2)
#
# PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-014 (AC-P3-2: dedup migration + rake check_duplicate_codes)
#
# Store-scoped single-code uniqueness for promotions:
#   - resolves existing duplicate single-code promotion rows (keep used, then
#     newest; never delete a used promotion — rename unused duplicates);
#   - adds a PG functional unique index (store_id, lower(btrim(code))).
#
# Rationale (PRD 附录 B): no new column — normalization (trim + downcase) is
# expressed by the index expression so existing read paths stay untouched.
class AddCodeUniquenessToPallasTradePromotions < ActiveRecord::Migration[8.1]
  INDEX_NAME = 'index_pallastrade_promotions_on_store_id_and_normalized_code'

  def up
    resolve_duplicate_codes

    execute <<~SQL.squish
      CREATE UNIQUE INDEX #{INDEX_NAME}
        ON pallastrade_promotions (store_id, lower(btrim(code)))
        WHERE code IS NOT NULL
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS #{INDEX_NAME}"
  end

  private

  # Groups single-code promotion rows by (store_id, lower(btrim(code))).
  # For each group with more than one row: keep the row that is used by an
  # order if any (else the newest), rename the rest to "<code>-dup-<id>".
  # If two *used* promotions share one code, abort with a manual list —
  # renaming a used promotion would silently change its public code.
  def resolve_duplicate_codes
    groups = select_duplicate_groups
    return if groups.empty?

    groups.each do |store_id, normalized|
      ids = promotion_ids_in_group(store_id, normalized)
      used = ids.select { |id| used_promotion?(id) }

      if used.size > 1
        raise "Cannot migrate: #{used.size} USED promotions share code '#{normalized}' " \
              "(ids: #{used.join(', ')}). Resolve manually before migrating."
      end

      keeper = used.first || newest_promotion_id(ids)
      (ids - [keeper]).each { |id| rename_duplicate(id, normalized) }
    end
  end

  def select_duplicate_groups
    rows = execute(<<~SQL.squish).to_a
      SELECT store_id, lower(btrim(code)) AS normalized
        FROM pallastrade_promotions
       WHERE code IS NOT NULL
       GROUP BY store_id, lower(btrim(code))
      HAVING COUNT(*) > 1
    SQL
    rows.map { |r| [r['store_id'], r['normalized']] }
  end

  def promotion_ids_in_group(store_id, normalized)
    execute(<<~SQL.squish).to_a.map { |r| r['id'] }
      SELECT id
        FROM pallastrade_promotions
       WHERE store_id = #{quote(store_id)}
         AND lower(btrim(code)) = #{quote(normalized)}
       ORDER BY id ASC
    SQL
  end

  def used_promotion?(id)
    execute(<<~SQL.squish).to_a.any?
      SELECT 1
        FROM pallastrade_order_promotions
       WHERE promotion_id = #{quote(id)}
       LIMIT 1
    SQL
  end

  def newest_promotion_id(ids)
    execute(<<~SQL.squish).to_a.first['id']
      SELECT id
        FROM pallastrade_promotions
       WHERE id IN (#{ids.map { |i| quote(i) }.join(',')})
       ORDER BY created_at DESC, id DESC
       LIMIT 1
    SQL
  end

  def rename_duplicate(id, normalized)
    new_code = "#{normalized}-dup-#{id}"[0, 250]
    execute(<<~SQL.squish)
      UPDATE pallastrade_promotions
         SET code = #{quote(new_code)}
       WHERE id = #{quote(id)}
    SQL
  end

  def quote(value)
    ActiveRecord::Base.connection.quote(value)
  end
end

namespace :pallastrade do
  namespace :upgrade do
    desc <<~DESC
      Populates +pallastrade_promotions.store_id+ and +pallastrade_payment_methods.store_id+
      from the legacy +pallastrade_promotions_stores+ / +pallastrade_payment_methods_stores+
      join tables. Idempotent — re-running skips records that already have a
      +store_id+.

      Run once after upgrading to PallasTrade 5.6+. Multi-store merchants must install
      +pallastrade_multi_store+ before running; without it, a record shared across
      several stores keeps only one owner (promotions: the earliest
      +pallastrade_promotions_stores+ row by +created_at+; payment methods: the lowest
      +store_id+, since that join has no timestamps) and the other stores lose
      the shared record. Each shared record is logged so the loss is visible.
    DESC
    task populate_single_store_associations: :environment do
      shared = Hash.new(0)

      if ActiveRecord::Base.connection.table_exists?(PallasTrade::StorePromotion.table_name)
        PallasTrade::Promotion.where(store_id: nil).find_each do |promotion|
          store_ids = PallasTrade::StorePromotion.where(promotion_id: promotion.id).order(:created_at, :store_id).pluck(:store_id)
          next if store_ids.empty?

          if store_ids.size > 1
            shared[:promotions] += 1
            PallasTrade::Deprecation.warn(
              "Promotion #{promotion.id} was shared across #{store_ids.size} stores; " \
              "assigning it to store #{store_ids.first}. Install pallastrade_multi_store to keep sharing."
            )
          end

          promotion.update_column(:store_id, store_ids.first)
        end
      else
        puts "  #{PallasTrade::StorePromotion.table_name} table not found — skipping promotions."
      end

      if ActiveRecord::Base.connection.table_exists?(PallasTrade::StorePaymentMethod.table_name)
        # +with_deleted+: PaymentMethod is paranoid, so soft-deleted rows would
        # otherwise be skipped and keep a NULL store_id.
        PallasTrade::PaymentMethod.with_deleted.where(store_id: nil).find_each do |payment_method|
          store_ids = PallasTrade::StorePaymentMethod.where(payment_method_id: payment_method.id).order(:store_id).pluck(:store_id)
          next if store_ids.empty?

          if store_ids.size > 1
            shared[:payment_methods] += 1
            PallasTrade::Deprecation.warn(
              "PaymentMethod #{payment_method.id} was shared across #{store_ids.size} stores; " \
              "assigning it to store #{store_ids.first}. Install pallastrade_multi_store to keep sharing."
            )
          end

          payment_method.update_column(:store_id, store_ids.first)
        end
      else
        puts "  #{PallasTrade::StorePaymentMethod.table_name} table not found — skipping payment methods."
      end

      if shared.values.sum.positive?
        puts "  #{shared[:promotions]} promotion(s) and #{shared[:payment_methods]} payment method(s) " \
             "were shared across stores — only the owner store keeps them unless pallastrade_multi_store is installed."
      end
    end
  end
end
